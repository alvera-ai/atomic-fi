defmodule Mix.Tasks.Corpus.Generate.SamlD do
  @shortdoc "SAML-D NDJSON sample → sharded AH/CP/PA/Txn corpus"

  @moduledoc """
  Reads the Python-subsetted SAML-D sample (NDJSON) produced by
  `make reseed-saml-d` and emits a K-shard replicated corpus under
  `--out`, ready for `mix corpus.validate <out> --concurrency K`.

  ## Pipeline

  ```
   make reseed-saml-d                                    ─► writes
     CORPUS_OUT=/big/disk/aml                            $CORPUS_OUT/saml-d/
     SAML_D_ROWS=1000                                       SAML-D.csv      (raw, 12 MB)
     SAML_D_SEED=0                                          saml_d.ndjson   (subset, small)

   mix corpus.generate.saml_d                            ─► writes
     --in /big/disk/aml/saml-d/saml_d.ndjson                <out>/
     --out /big/disk/aml/sharded/saml-d                        shard-00/…
     --shards 8                                                shard-01/…
                                                              …
                                                              shard-07/…

   mix corpus.validate /big/disk/aml/sharded/saml-d --concurrency 8
                                                       ─► K-way parallel
                                                          run through the
                                                          production write
                                                          path; markdown
                                                          report + timing.
  ```

  ## SAML-D columns we read

      Sender_account, Receiver_account, Amount, Payment_currency,
      Payment_type, Is_laundering

  Other SAML-D fields (Date / Time / locations / Laundering_type) are
  passed through into the txn's `_label.scenario` string so the bench
  report keeps them visible in the markdown output.

  ## Schema mapping

  ```
   SAML-D row                          atomic-fi entity
   ────────────────────────────────────────────────────────────────
   Sender_account                  ─►  AccountHolder (individual,
                                       kyc=approved) + one wallet PA
   Receiver_account                ─►  Counterparty (under sender AH)
                                       + one wallet PA owned by it
   Amount, Payment_currency        ─►  Transaction (amount + currency)
   Payment_type                    ─►  Transaction.transaction_type
                                       (mapped via SAML-D string → enum)
   Is_laundering (0/1)             ─►  _expected.status — `accepted`
                                       when 0, otherwise `accepted`
                                       too (most laundering labels
                                       won't be caught by the active
                                       rule set; the bench measures
                                       throughput, not catch-rate).
                                       The `_label.scenario` carries
                                       Laundering_type for auditability.
  ```

  Account dedup: each `Sender_account` becomes ONE AH; each
  `Receiver_account` becomes ONE CP. Repeat appearances of the same
  account across rows share the same external_id within the shard.
  """

  use Mix.Task

  alias AtomicFi.Corpus.Shard

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          in: :string,
          out: :string,
          shards: :integer
        ]
      )

    in_path =
      opts[:in] ||
        Mix.raise("--in <path/to/saml_d.ndjson> is required (run `make reseed-saml-d` first)")

    out_dir =
      opts[:out] ||
        Mix.raise("--out <sharded_dir> is required (sharded corpus root, outside repo)")

    shards = Keyword.get(opts, :shards, 4)

    rows = Shard.read_ndjson!(in_path)
    Mix.shell().info("→ read #{length(rows)} rows from #{in_path}")

    Shard.emit(rows,
      out: out_dir,
      shards: shards,
      mapper: &shard_mapper(&1, &2)
    )
  end

  # ── per-shard mapper ───────────────────────────────────────────────
  #
  # Replicated across K shards, each invocation gets the SAME `rows`
  # list and its own `prefix`. The prefix scopes every external_id so
  # concurrent shard runs don't collide on the per-tenant unique
  # indexes.

  defp shard_mapper(rows, prefix) do
    senders = rows |> Enum.map(& &1["Sender_account"]) |> Enum.uniq()
    receivers = rows |> Enum.map(& &1["Receiver_account"]) |> Enum.uniq()

    ah_lines =
      senders
      |> Enum.with_index()
      |> Enum.map(fn {sender, idx} -> ah_row(prefix, idx, sender) end)

    cp_lines =
      receivers
      |> Enum.with_index()
      |> Enum.map(fn {receiver, idx} ->
        # Park every CP under the first sender as its host AH — SAML-D
        # rows don't track CP ownership, so a single AH-anchor is the
        # most conservative choice (RLS partition).
        cp_row(prefix, idx, receiver, ah_external_id(prefix, 0))
      end)

    pa_lines =
      Enum.with_index(senders)
      |> Enum.map(fn {_sender, idx} ->
        sender_pa_row(prefix, idx)
      end)
      |> Enum.concat(
        Enum.with_index(receivers)
        |> Enum.map(fn {_receiver, idx} ->
          receiver_pa_row(prefix, idx)
        end)
      )

    sender_index = Enum.with_index(senders) |> Map.new(fn {s, i} -> {s, i} end)
    receiver_index = Enum.with_index(receivers) |> Map.new(fn {r, i} -> {r, i} end)

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

  defp ah_row(prefix, idx, _sender_account) do
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

  defp cp_row(prefix, idx, _receiver_account, host_ah_ext) do
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
      "counterparty_external_id" => cp_external_id(prefix, idx),
      "account_type" => "wallet",
      "currency" => "USD"
    })
  end

  defp txn_row(prefix, idx, row, sender_index, receiver_index) do
    sender_idx = Map.fetch!(sender_index, row["Sender_account"])
    receiver_idx = Map.fetch!(receiver_index, row["Receiver_account"])
    amount = round(row["Amount"] || 100)
    currency = row["Payment_currency"] || "USD"

    laundering_type = row["Laundering_type"] || "Normal"
    payment_type = row["Payment_type"] || "Cash Deposit"
    date = row["Date"] || ""

    Jason.encode!(%{
      "external_id" => "#{prefix}txn-#{pad(idx)}",
      "transaction_type" => map_payment_type(payment_type),
      "amount" => amount,
      "currency" => currency,
      "account_holder_external_id" => ah_external_id(prefix, sender_idx),
      "debtor_payment_account_external_id" => sender_pa_external_id(prefix, sender_idx),
      "creditor_payment_account_external_id" => receiver_pa_external_id(prefix, receiver_idx),
      "_label" => %{
        "regime" => "saml-d",
        "cite" => "Oztas et al. 2023 — SAML-D synthetic monitoring dataset",
        "scenario" => "type=#{payment_type} laundering_type=#{laundering_type} date=#{date}"
      },
      "_expected" => %{
        "status" => "accepted",
        "rejected_rule" => nil
      }
    })
  end

  # SAML-D's Payment_type vocabulary is operational ("Cash Deposit",
  # "Cheque", "Wire Transfer", "Credit Card", "Cross-border", "ACH", …);
  # atomic-fi's Transaction.transaction_type is the ISO 20022 family
  # (credit_transfer / direct_debit / internal_transfer / refund). Map
  # conservatively — anything credit-like → :credit_transfer, anything
  # debit-pull-like → :direct_debit, fall back to :credit_transfer.
  defp map_payment_type(value) when is_binary(value) do
    v = String.downcase(value)

    cond do
      String.contains?(v, "debit") -> "direct_debit"
      String.contains?(v, "ach") -> "credit_transfer"
      String.contains?(v, "wire") -> "credit_transfer"
      String.contains?(v, "cross") -> "credit_transfer"
      String.contains?(v, "card") -> "credit_transfer"
      String.contains?(v, "cheque") -> "credit_transfer"
      String.contains?(v, "cash") -> "credit_transfer"
      true -> "credit_transfer"
    end
  end

  defp map_payment_type(_), do: "credit_transfer"

  defp ah_external_id(prefix, idx), do: "#{prefix}ah-#{pad(idx)}"
  defp cp_external_id(prefix, idx), do: "#{prefix}cp-#{pad(idx)}"
  defp sender_pa_external_id(prefix, idx), do: "#{prefix}pa-snd-#{pad(idx)}"
  defp receiver_pa_external_id(prefix, idx), do: "#{prefix}pa-rcv-#{pad(idx)}"

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(6, "0")
end
