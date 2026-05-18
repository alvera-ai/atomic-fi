defmodule Mix.Tasks.Corpus.Generate.Amlgentex do
  @shortdoc "AMLGentex NDJSON sample → sharded AH/CP/PA/Txn corpus"

  @moduledoc """
  Reads the Python-subsetted AMLGentex sample (NDJSON) produced by
  `make reseed-amlgentex` and emits a K-shard replicated corpus under
  `--out`, ready for `mix corpus.validate <out> --concurrency K`.

  ## Pipeline

  ```
   make reseed-amlgentex                                 ─► writes
     CORPUS_OUT=/big/disk/aml                            $CORPUS_OUT/amlgentex/
     AMLGENTEX_ROWS=1000                                    repo/                  (cloned upstream)
     AMLGENTEX_SEED=0                                       transactions.parquet   (sim output)
                                                            amlgentex.ndjson       (subset, small)

   mix corpus.generate.amlgentex
     --in /big/disk/aml/amlgentex/amlgentex.ndjson      ─► writes
     --out /big/disk/aml/sharded/amlgentex                  <out>/shard-NN/…
     --shards 8
  ```

  ## AMLGentex columns we read

  The AMLGentex simulator's exact parquet schema is governed by
  `corpus/upstream/amlgentex/config/data.yaml`; the common-case columns
  this mapper reads are:

      Sender, Receiver, Amount, Currency, Timestamp, Is_SAR (or
      AlertID-like label fields)

  Field names that don't exist in a given AMLGentex output fall back to
  sensible defaults so a config change doesn't crash the generator —
  the mapping is intentionally forgiving.

  ## Schema mapping

  ```
   AMLGentex row                          atomic-fi entity
   ────────────────────────────────────────────────────────────────
   Sender                             ─►  AccountHolder (individual,
                                          kyc=approved) + one wallet PA
   Receiver                           ─►  Counterparty (under sender AH)
                                          + one wallet PA owned by it
   Amount, Currency                   ─►  Transaction (amount + currency)
   Is_SAR (or any "alert" label)      ─►  _expected.status — always
                                          `accepted` (AMLGentex SAR
                                          patterns are graph-level
                                          typologies the active rule
                                          set doesn't fire on; the
                                          label is recorded in
                                          _label.scenario for audit).
  ```
  """

  use Mix.Task

  alias AtomicFi.Corpus.Shard
  alias AtomicFi.Corpus.SyntheticSeed

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          in: :string,
          out: :string,
          shards: :integer,
          synthetic: :boolean,
          rows: :integer,
          seed: :integer
        ]
      )

    out_dir =
      opts[:out] ||
        Mix.raise("--out <sharded_dir> is required (sharded corpus root, outside repo)")

    shards = Keyword.get(opts, :shards, 4)

    rows =
      cond do
        Keyword.get(opts, :synthetic, false) ->
          row_count = Keyword.get(opts, :rows, 1000)
          rng_seed = Keyword.get(opts, :seed, 0)

          Mix.shell().info(
            "→ generating #{row_count} synthetic AMLGentex-shape rows (seed=#{rng_seed})"
          )

          SyntheticSeed.amlgentex(row_count, rng_seed)

        opts[:in] != nil ->
          Mix.shell().info("→ reading rows from #{opts[:in]}")
          Shard.read_ndjson!(opts[:in])

        true ->
          Mix.raise(
            "either --in <path/to/amlgentex.ndjson> (run `make reseed-amlgentex` first) " <>
              "or --synthetic --rows N (hardcoded AMLGentex-shape generator, no external deps) is required"
          )
      end

    Mix.shell().info("→ #{length(rows)} rows ready")

    Shard.emit(rows,
      out: out_dir,
      shards: shards,
      mapper: &shard_mapper(&1, &2)
    )
  end

  # AMLGentex columns we tolerate (any one present is enough):
  #   Sender, sender, sender_account, sender_id, Source
  #   Receiver, receiver, receiver_account, receiver_id, Target
  #   Amount, amount, value
  #   Currency, currency
  #   Is_SAR, is_sar, alert, label, sar_label

  defp shard_mapper(rows, prefix) do
    senders = rows |> Enum.map(&extract_sender/1) |> Enum.uniq()
    receivers = rows |> Enum.map(&extract_receiver/1) |> Enum.uniq()

    ah_lines =
      Enum.with_index(senders)
      |> Enum.map(fn {_sender, idx} -> ah_row(prefix, idx) end)

    cp_lines =
      Enum.with_index(receivers)
      |> Enum.map(fn {_receiver, idx} -> cp_row(prefix, idx, ah_external_id(prefix, 0)) end)

    pa_lines =
      Enum.with_index(senders)
      |> Enum.map(fn {_sender, idx} -> sender_pa_row(prefix, idx) end)
      |> Enum.concat(
        Enum.with_index(receivers)
        |> Enum.map(fn {_receiver, idx} -> receiver_pa_row(prefix, idx) end)
      )

    sender_index = senders |> Enum.with_index() |> Map.new()
    receiver_index = receivers |> Enum.with_index() |> Map.new()

    txn_lines =
      rows
      |> Enum.with_index()
      |> Enum.map(fn {row, idx} ->
        txn_row(prefix, idx, row, sender_index, receiver_index)
      end)

    %{
      account_holders: ah_lines,
      counterparties: cp_lines,
      payment_accounts: pa_lines,
      transactions: txn_lines
    }
  end

  defp extract_sender(row),
    do: row["Sender"] || row["sender"] || row["sender_id"] || row["Source"]

  defp extract_receiver(row),
    do: row["Receiver"] || row["receiver"] || row["receiver_id"] || row["Target"]

  defp extract_amount(row) do
    raw = row["Amount"] || row["amount"] || row["value"] || 100
    raw |> to_number() |> round() |> max(1)
  end

  defp extract_currency(row), do: row["Currency"] || row["currency"] || "USD"

  defp extract_sar_label(row) do
    Map.get(row, "Is_SAR") || Map.get(row, "is_sar") || Map.get(row, "label") || 0
  end

  defp to_number(n) when is_integer(n), do: n
  defp to_number(n) when is_float(n), do: n
  defp to_number(n) when is_binary(n), do: String.to_float(n) |> trunc()
  defp to_number(_), do: 1

  defp ah_row(prefix, idx) do
    Jason.encode!(%{
      "external_id" => ah_external_id(prefix, idx),
      "account_holder_type" => "individual",
      "status" => "pending",
      "kyc_status" => "approved",
      "risk_level" => "low",
      "enabled_currencies" => ["USD"],
      "chain_screening" => false,
      "legal_entity" => %{
        "legal_entity_type" => "individual",
        "first_name" => "Sender",
        "last_name" => "Idx#{idx}"
      }
    })
  end

  defp cp_row(prefix, idx, host_ah_ext) do
    Jason.encode!(%{
      "external_id" => cp_external_id(prefix, idx),
      "account_holder_external_id" => host_ah_ext,
      "status" => "active",
      "chain_screening" => false,
      "legal_entity" => %{
        "legal_entity_type" => "individual",
        "first_name" => "Receiver",
        "last_name" => "Idx#{idx}"
      }
    })
  end

  defp sender_pa_row(prefix, idx) do
    Jason.encode!(%{
      "external_id" => sender_pa_external_id(prefix, idx),
      "account_holder_external_id" => ah_external_id(prefix, idx),
      "account_type" => "wallet",
      "currency" => "USD"
    })
  end

  defp receiver_pa_row(prefix, idx) do
    Jason.encode!(%{
      "external_id" => receiver_pa_external_id(prefix, idx),
      # CP-owned PA: host AH is the first sender (same anchor used by
      # the CP rows). counterparty_external_id ties PA to its CP.
      "account_holder_external_id" => ah_external_id(prefix, 0),
      "counterparty_external_id" => cp_external_id(prefix, idx),
      "account_type" => "wallet",
      "currency" => "USD"
    })
  end

  defp txn_row(prefix, idx, row, sender_index, receiver_index) do
    sender = extract_sender(row)
    receiver = extract_receiver(row)
    sender_idx = Map.fetch!(sender_index, sender)
    receiver_idx = Map.fetch!(receiver_index, receiver)
    amount = extract_amount(row)
    currency = extract_currency(row)
    sar = extract_sar_label(row)

    # No `_expected` — bulk-bench rows are uncalibrated synthetic data,
    # not hand-tuned scenario fixtures. corpus.validate reports them
    # under "new (no _expected)".
    Jason.encode!(%{
      "external_id" => "#{prefix}txn-#{pad(idx)}",
      "transaction_type" => "credit_transfer",
      "amount" => amount,
      "currency" => currency,
      "account_holder_external_id" => ah_external_id(prefix, sender_idx),
      "debtor_payment_account_external_id" => sender_pa_external_id(prefix, sender_idx),
      "creditor_payment_account_external_id" => receiver_pa_external_id(prefix, receiver_idx),
      "_label" => %{
        "regime" => "amlgentex",
        "cite" => "AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network",
        "scenario" => "is_sar=#{sar}"
      }
    })
  end

  defp ah_external_id(prefix, idx), do: "#{prefix}ah-#{pad(idx)}"
  defp cp_external_id(prefix, idx), do: "#{prefix}cp-#{pad(idx)}"
  defp sender_pa_external_id(prefix, idx), do: "#{prefix}pa-snd-#{pad(idx)}"
  defp receiver_pa_external_id(prefix, idx), do: "#{prefix}pa-rcv-#{pad(idx)}"

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(6, "0")
end
