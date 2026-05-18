defmodule Mix.Tasks.Corpus.Generate.Stableaml do
  @shortdoc "StableAML CSV → deterministic NDJSON sample, rule JSON, and/or sharded corpus"

  @moduledoc """
  Three modes — pick whichever artefact(s) you want, all driven from the
  same FINOS Labs StableAML Category-1 (sanctioned wallets) CSV.

  Source layout (populated by `make reseed-stableaml`):

      $CORPUS_ROOT/stableaml/address_sanctioned.csv
        — three columns, no header: blockchain, wallet_address, flag
        — Category 1: OFAC-listed, SEC-flagged, Tether/Circle-frozen
        — 807 rows, ~52 kB

  ## Modes

  ### default — sample as NDJSON (smoke / pipeline check)

      $ mix corpus.generate.stableaml --wallets 100 --seed 0

  Writes `tmp/corpus/<seed>/stableaml/wallet_addresses.ndjson` — one
  labelled row per sampled wallet. Useful for piping into ad-hoc
  consumers.

  ### --emit-rule — bake the full list into the JDM rule

      $ mix corpus.generate.stableaml --emit-rule

  Rewrites `priv/zenrule/transaction-screening/stableaml_wallet_blocklist.json`
  with all 807 wallet addresses baked into the functionNode's
  SANCTIONED_WALLETS set. Re-run after `make reseed-stableaml` when the
  upstream refreshes. Byte-stable per input CSV — same csv → same JSON.

  ### --emit-corpus — flat seed corpus (k6 VU fan-out handled by validate)

      $ mix corpus.generate.stableaml --emit-corpus --txns 1000 --seed 0

  Writes `corpus/zen_rules/stableaml_wallet_blocklist/`:

      account_holders.ndjson           ← FK parents (sender + receiver AHs)
      counterparties.ndjson            ← sanctioned wallet CP owners
      payment_accounts.ndjson          ← sender PA + sanctioned PAs + clean
      transactions.ndjson              ← txn rows in deterministic order

  Sharding is no longer on-disk. `mix corpus.validate --concurrency K`
  fans the seed out into K virtual users at runtime (each with its own
  id prefix), so K is a runtime knob rather than baked into the corpus.

  Three buckets, evenly distributed:

    * sanctioned wallet on creditor → `stableaml_wallet_blocklist` BLOCK
    * recipient AH kyc=in_progress  → `stablecoin_block_unverified` BLOCK
    * clean wallet + approved kyc   → PASS

  All sender debits are USD 12,000 to dodge the sub-CTR band that
  trips `ctr_structuring`.

  ## Options

    * `--seed <int>`        RNG seed (default 0).
    * `--wallets <N|all>`   sample size for default-mode NDJSON
                            (default 100).
    * `--in <path>`         override source CSV.
    * `--out <path>`        override default-mode NDJSON dir.
    * `--emit-rule`         (flag) write priv/zenrule rule from CSV.
    * `--emit-corpus`       (flag) write corpus/zen_rules folder.
    * `--txns <N>`          total transactions in --emit-corpus mode
                            (default 100).

  No external service contact, no docker — pure file I/O.
  """

  use Mix.Task

  @rule_path "priv/zenrule/transaction-screening/stableaml_wallet_blocklist.json"
  @corpus_path "corpus/zen_rules/stableaml_wallet_blocklist"

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          seed: :integer,
          wallets: :string,
          in: :string,
          out: :string,
          emit_rule: :boolean,
          emit_corpus: :boolean,
          emit_shards: :boolean,
          shards: :integer,
          txns: :integer
        ]
      )

    seed = Keyword.get(opts, :seed, 0)
    in_path = Keyword.get(opts, :in, default_in_path())
    rows = read_csv!(in_path)

    cond do
      Keyword.get(opts, :emit_rule, false) ->
        emit_rule(rows)

      Keyword.get(opts, :emit_corpus, false) ->
        txns = Keyword.get(opts, :txns, 100)
        emit_corpus(rows, txns, seed)

      Keyword.get(opts, :emit_shards, false) ->
        out_dir =
          opts[:out] ||
            Mix.raise(
              "--emit-shards requires --out <dir> (the sharded corpus root, outside repo)"
            )

        shards = Keyword.get(opts, :shards, 4)
        txns = Keyword.get(opts, :txns, 100)
        emit_shards(rows, %{out: out_dir, shards: shards, txns: txns, seed: seed})

      true ->
        wallets = parse_wallets(Keyword.get(opts, :wallets, "100"))
        out_dir = Keyword.get(opts, :out, default_out_dir(seed))
        emit_default(rows, wallets, seed, out_dir)
    end
  end

  # ─── default mode ────────────────────────────────────────────────────

  defp emit_default(rows, wallets, seed, out_dir) do
    sampled = sample(rows, wallets, seed)
    File.mkdir_p!(out_dir)
    out_path = Path.join(out_dir, "wallet_addresses.ndjson")
    write_ndjson!(out_path, Enum.map(sampled, &label_row/1))

    Mix.shell().info(
      "→ wrote #{length(sampled)} / #{length(rows)} rows to #{out_path} (seed=#{seed})"
    )
  end

  # ─── --emit-rule ─────────────────────────────────────────────────────

  defp emit_rule(rows) do
    wallets =
      rows
      |> Enum.map(&String.downcase(&1["wallet_address"]))
      |> Enum.sort()
      |> Enum.uniq()

    js_array =
      wallets
      |> Enum.map(&"  '#{&1}'")
      |> Enum.join(",\n")

    source = """
    /**
     * StableAML wallet-address blocklist (OFAC 31 CFR §501.404; GENIUS §4(a)(5)).
     *
     * AUTO-GENERATED by `mix corpus.generate.stableaml --emit-rule`. Do not
     * edit by hand. Re-run after `make reseed-stableaml` when the upstream
     * sha changes. The sanctioned-wallet set is the Category-1 slice of
     * FINOS Labs StableAML — OFAC-listed, SEC-flagged, Tether/Circle-frozen
     * addresses. See corpus/upstream/stableaml/manifest.json for the
     * pinned upstream sha256.
     *
     * Maps to use-cases.md scenario #34 — sending stablecoin to an OFAC-
     * designated wallet blocks the transfer and triggers an OFAC blocked-
     * property report.
     */
    const SANCTIONED_WALLETS = new Set([
    #{js_array}
    ]);

    export const handler = async (input) => {
      const creditor = input.creditor_payment_account;
      if (!creditor) return { ledger_accounts: {} };

      const addr = creditor.wallet_address;
      if (typeof addr !== 'string') return { ledger_accounts: {} };
      if (!SANCTIONED_WALLETS.has(addr.toLowerCase())) return { ledger_accounts: {} };

      const las = creditor.las || [];
      const ledger_accounts = {};
      for (const la of las) {
        ledger_accounts[la.id] = {
          daily_debit_cap: 0,
          daily_credit_cap: 0,
          reason: 'stableaml_wallet_blocklist',
          block_reason: 'stableaml_wallet_blocklist',
          is_blocked: true
        };
      }
      return { ledger_accounts };
    };
    """

    jdm = %{
      "contentType" => "application/vnd.gorules.decision",
      "nodes" => [
        %{
          "id" => "request",
          "type" => "inputNode",
          "name" => "Request",
          "position" => %{"x" => 100, "y" => 160}
        },
        %{
          "id" => "stableaml_gate",
          "type" => "functionNode",
          "name" => "StableAML Wallet Blocklist",
          "position" => %{"x" => 380, "y" => 160},
          "content" => %{"source" => source}
        },
        %{
          "id" => "response",
          "type" => "outputNode",
          "name" => "Response",
          "position" => %{"x" => 700, "y" => 160}
        }
      ],
      "edges" => [
        %{
          "id" => "edge_request_stableaml",
          "type" => "edge",
          "sourceId" => "request",
          "targetId" => "stableaml_gate"
        },
        %{
          "id" => "edge_stableaml_response",
          "type" => "edge",
          "sourceId" => "stableaml_gate",
          "targetId" => "response"
        }
      ]
    }

    File.write!(@rule_path, Jason.encode!(jdm, pretty: true) <> "\n")
    Mix.shell().info("→ wrote #{length(wallets)} wallets into #{@rule_path}")
  end

  # ─── --emit-shards ───────────────────────────────────────────────────
  #
  # Produces K replicated shard folders under --out, each containing a
  # full corpus (account_holders / counterparties / payment_accounts /
  # transactions ndjson) prefixed with a shard-unique external_id
  # namespace. Same logical workload as --emit-corpus, but laid out for
  # `mix corpus.validate <out> --concurrency K` to run all shards in
  # parallel as K independent VUs against the engine.
  #
  # --out is mandatory and is expected to live OUTSIDE the repo (e.g.
  # under $CORPUS_OUT/sharded/stableaml/); committed corpora are in
  # corpus/zen_rules/<slug>/ via --emit-corpus.

  defp emit_shards(rows, %{out: out, shards: shards, txns: txns, seed: seed}) do
    sanctioned = sample(rows, txns, seed)

    AtomicFi.Corpus.Shard.emit(sanctioned,
      out: out,
      shards: shards,
      mapper: &shard_mapper(&1, &2)
    )
  end

  defp shard_mapper(sanctioned_rows, prefix) do
    ah_lines = [
      ah_row("#{prefix}ah-sender", "approved", "Alice", "Sender"),
      ah_row("#{prefix}ah-clean", "approved", "Charlie", "Clean"),
      ah_row("#{prefix}ah-in-progress", "in_progress", "Patty", "Pending")
    ]

    {cp_lines, pa_dyn_lines, txn_lines} = build_shard_buckets(sanctioned_rows, prefix)

    pa_static_lines = [
      pa_row("#{prefix}pa-sender", account_holder_external_id: "#{prefix}ah-sender"),
      pa_row("#{prefix}pa-clean-recipient", account_holder_external_id: "#{prefix}ah-clean"),
      pa_row("#{prefix}pa-in-progress-recipient",
        account_holder_external_id: "#{prefix}ah-in-progress"
      )
    ]

    %{
      account_holders: ah_lines,
      counterparties: cp_lines,
      payment_accounts: pa_static_lines ++ pa_dyn_lines,
      transactions: txn_lines
    }
  end

  defp build_shard_buckets(sanctioned_rows, prefix) do
    sanctioned_rows
    |> Enum.with_index()
    |> Enum.reduce({[], [], []}, fn {row, idx}, {cps, pas, txns} ->
      bucket = rem(idx, 3)
      slug = pad(idx)

      case bucket do
        0 ->
          cp_ext = "#{prefix}cp-sanc-#{slug}"
          pa_ext = "#{prefix}pa-sanc-#{slug}"
          addr = String.downcase(row["wallet_address"])

          cp = cp_row(cp_ext, "#{prefix}ah-sender", "Sanc-#{slug}", "Holder")

          pa =
            pa_row(pa_ext,
              account_holder_external_id: "#{prefix}ah-sender",
              counterparty_external_id: cp_ext,
              account_type: "wallet",
              wallet_address: addr,
              wallet_chain: "ETH"
            )

          txn =
            shard_txn_row("#{prefix}txn-#{slug}-sanc",
              ah: "#{prefix}ah-sender",
              debtor_pa: "#{prefix}pa-sender",
              creditor_pa: pa_ext,
              scenario: "sanctioned wallet #{addr} — BLOCK",
              expected_status: "rejected",
              expected_rule: "stableaml_wallet_blocklist"
            )

          {[cp | cps], [pa | pas], [txn | txns]}

        1 ->
          txn =
            shard_txn_row("#{prefix}txn-#{slug}-kyc",
              ah: "#{prefix}ah-sender",
              debtor_pa: "#{prefix}pa-sender",
              creditor_pa: "#{prefix}pa-in-progress-recipient",
              scenario: "recipient kyc=in_progress — de_minimis BLOCK",
              expected_status: "rejected",
              expected_rule: "stablecoin_block_unverified"
            )

          {cps, pas, [txn | txns]}

        2 ->
          txn =
            shard_txn_row("#{prefix}txn-#{slug}-clean",
              ah: "#{prefix}ah-sender",
              debtor_pa: "#{prefix}pa-sender",
              creditor_pa: "#{prefix}pa-clean-recipient",
              scenario: "clean wallet + approved kyc — PASS",
              expected_status: "accepted",
              expected_rule: nil
            )

          {cps, pas, [txn | txns]}
      end
    end)
    |> then(fn {cps, pas, txns} -> {Enum.reverse(cps), Enum.reverse(pas), Enum.reverse(txns)} end)
  end

  defp shard_txn_row(ext, opts) do
    Jason.encode!(%{
      "external_id" => ext,
      "transaction_type" => "internal_transfer",
      "amount" => 12_000,
      "currency" => "USD",
      "account_holder_external_id" => Keyword.fetch!(opts, :ah),
      "debtor_payment_account_external_id" => Keyword.fetch!(opts, :debtor_pa),
      "creditor_payment_account_external_id" => Keyword.fetch!(opts, :creditor_pa),
      "_label" => %{
        "regime" => "ofac",
        "cite" => "31 CFR §501.404 + GENIUS §4(a)(5)",
        "scenario" => Keyword.fetch!(opts, :scenario)
      },
      "_expected" => %{
        "status" => Keyword.fetch!(opts, :expected_status),
        "rejected_rule" => Keyword.fetch!(opts, :expected_rule)
      }
    })
  end

  # ─── --emit-corpus ───────────────────────────────────────────────────

  defp emit_corpus(rows, txns, seed) do
    File.mkdir_p!(@corpus_path)

    # Static parents — one sender AH/PA, plus a clean recipient AH/PA.
    File.write!(
      Path.join(@corpus_path, "account_holders.ndjson"),
      Enum.join(
        [
          ah_row("saw-ah-sender", "approved", "Alice", "Sender"),
          ah_row("saw-ah-clean", "approved", "Charlie", "Clean"),
          ah_row("saw-ah-in-progress", "in_progress", "Patty", "Pending")
        ],
        "\n"
      ) <> "\n"
    )

    sanctioned = sample(rows, txns, seed)

    {cps, pas_dyn, txns_rows} = build_dynamic(sanctioned, seed)

    File.write!(
      Path.join(@corpus_path, "counterparties.ndjson"),
      Enum.join(cps, "\n") <> if(cps == [], do: "", else: "\n")
    )

    pas_static = [
      pa_row("saw-pa-sender", account_holder_external_id: "saw-ah-sender"),
      pa_row("saw-pa-clean-recipient", account_holder_external_id: "saw-ah-clean"),
      pa_row("saw-pa-in-progress-recipient", account_holder_external_id: "saw-ah-in-progress")
    ]

    File.write!(
      Path.join(@corpus_path, "payment_accounts.ndjson"),
      Enum.join(pas_static ++ pas_dyn, "\n") <> "\n"
    )

    File.write!(
      Path.join(@corpus_path, "transactions.ndjson"),
      Enum.join(txns_rows, "\n") <> if(txns_rows == [], do: "", else: "\n")
    )

    Mix.shell().info(
      "→ wrote corpus: #{length(txns_rows)} txns at #{@corpus_path} (use `mix corpus.validate --concurrency K` to fan out)"
    )
  end

  # Builds the txn list + the dynamic CPs/PAs required for sanctioned-wallet
  # creditor sides. The three buckets are interleaved deterministically by
  # index modulo 3, so any prefix of the list still covers all three
  # branches.
  defp build_dynamic(sanctioned_rows, _seed) do
    sanctioned_rows
    |> Enum.with_index()
    |> Enum.reduce({[], [], []}, fn {row, idx}, {cps, pas, txns} ->
      bucket = rem(idx, 3)
      slug = pad(idx)

      case bucket do
        # bucket A: sanctioned wallet on a CP-owned creditor PA
        0 ->
          cp_ext = "saw-cp-sanc-#{slug}"
          pa_ext = "saw-pa-sanc-#{slug}"
          addr = String.downcase(row["wallet_address"])

          cp =
            cp_row(cp_ext, "saw-ah-sender", "Sanc-#{slug}", "Holder")

          pa =
            pa_row(pa_ext,
              account_holder_external_id: "saw-ah-sender",
              counterparty_external_id: cp_ext,
              account_type: "wallet",
              wallet_address: addr,
              wallet_chain: "ETH"
            )

          txn =
            txn_row("saw-txn-#{slug}-sanc",
              creditor_pa: pa_ext,
              scenario: "sanctioned wallet #{addr} — BLOCK",
              expected_status: "rejected",
              expected_rule: "stableaml_wallet_blocklist"
            )

          {[cp | cps], [pa | pas], [txn | txns]}

        # bucket B: recipient AH kyc=in_progress (no wallet, no rule about it)
        1 ->
          txn =
            txn_row("saw-txn-#{slug}-kyc",
              creditor_pa: "saw-pa-in-progress-recipient",
              scenario: "recipient kyc=in_progress — de_minimis BLOCK",
              expected_status: "rejected",
              expected_rule: "stablecoin_block_unverified"
            )

          {cps, pas, [txn | txns]}

        # bucket C: clean
        2 ->
          txn =
            txn_row("saw-txn-#{slug}-clean",
              creditor_pa: "saw-pa-clean-recipient",
              scenario: "clean wallet + approved kyc — PASS",
              expected_status: "accepted",
              expected_rule: nil
            )

          {cps, pas, [txn | txns]}
      end
    end)
    |> then(fn {cps, pas, txns} -> {Enum.reverse(cps), Enum.reverse(pas), Enum.reverse(txns)} end)
  end

  defp ah_row(ext, kyc, fname, lname) do
    Jason.encode!(%{
      "external_id" => ext,
      "account_holder_type" => "individual",
      "status" => "pending",
      "kyc_status" => kyc,
      "risk_level" => "low",
      "enabled_currencies" => ["USD"],
      "legal_entity" => %{
        "legal_entity_type" => "individual",
        "first_name" => fname,
        "last_name" => lname
      }
    })
  end

  defp cp_row(ext, parent_ah_ext, fname, lname) do
    Jason.encode!(%{
      "external_id" => ext,
      "account_holder_external_id" => parent_ah_ext,
      "status" => "active",
      "chain_screening" => false,
      "legal_entity" => %{
        "legal_entity_type" => "individual",
        "first_name" => fname,
        "last_name" => lname
      }
    })
  end

  defp pa_row(ext, opts) do
    base = %{
      "external_id" => ext,
      "account_type" => Keyword.get(opts, :account_type, "wallet"),
      "currency" => "USD"
    }

    base
    |> maybe_put(opts, :account_holder_external_id)
    |> maybe_put(opts, :counterparty_external_id)
    |> maybe_put(opts, :wallet_address)
    |> maybe_put(opts, :wallet_chain)
    |> Jason.encode!()
  end

  defp maybe_put(map, opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, v} -> Map.put(map, Atom.to_string(key), v)
      :error -> map
    end
  end

  defp txn_row(ext, opts) do
    Jason.encode!(%{
      "external_id" => ext,
      "transaction_type" => "internal_transfer",
      "amount" => 12_000,
      "currency" => "USD",
      "account_holder_external_id" => "saw-ah-sender",
      "debtor_payment_account_external_id" => "saw-pa-sender",
      "creditor_payment_account_external_id" => Keyword.fetch!(opts, :creditor_pa),
      "_label" => %{
        "regime" => "ofac",
        "cite" => "31 CFR §501.404 + GENIUS §4(a)(5)",
        "scenario" => Keyword.fetch!(opts, :scenario)
      },
      "_expected" => %{
        "status" => Keyword.fetch!(opts, :expected_status),
        "rejected_rule" => Keyword.fetch!(opts, :expected_rule)
      }
    })
  end

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(4, "0")

  # ─── shared helpers ──────────────────────────────────────────────────

  defp default_in_path do
    root =
      System.get_env("ATOMIC_FI_CORPUS_ROOT") ||
        Path.join(System.user_home!(), ".local/share/atomic-fi/corpus")

    Path.join([root, "stableaml", "address_sanctioned.csv"])
  end

  defp default_out_dir(seed),
    do: Path.join(["tmp", "corpus", Integer.to_string(seed), "stableaml"])

  defp parse_wallets("all"), do: :all
  defp parse_wallets(str), do: String.to_integer(str)

  defp read_csv!(path) do
    unless File.exists?(path) do
      Mix.raise(
        "StableAML CSV not found at #{path}\n" <>
          "Run `make reseed-stableaml` to fetch it, or pass --in <path>."
      )
    end

    path
    |> File.stream!()
    |> Stream.map(&String.trim_trailing(&1, "\n"))
    |> Stream.reject(&(&1 == ""))
    |> Enum.map(&parse_row!/1)
  end

  defp parse_row!(line) do
    case String.split(line, ",", parts: 3) do
      [blockchain, wallet_address, flag] ->
        %{"blockchain" => blockchain, "wallet_address" => wallet_address, "flag" => flag}

      _ ->
        Mix.raise("malformed CSV row (expected 3 comma-separated fields): #{inspect(line)}")
    end
  end

  defp sample(rows, :all, _seed), do: rows

  defp sample(rows, n, _seed) when is_integer(n) and n >= length(rows), do: rows

  defp sample(rows, n, seed) when is_integer(n) and n > 0 do
    _ = :rand.seed(:exsss, {seed, seed, seed})

    rows
    |> Enum.map(&{:rand.uniform(), &1})
    |> Enum.sort()
    |> Enum.take(n)
    |> Enum.map(fn {_, row} -> row end)
  end

  defp write_ndjson!(path, rows) do
    body =
      rows
      |> Enum.map(&Jason.encode!/1)
      |> Enum.intersperse("\n")

    File.write!(path, [body, "\n"])
  end

  defp label_row(row) do
    Map.put(row, "_label", %{
      "source" => "stableaml",
      "category" => "sanctioned",
      "regime" => "ofac",
      "cite" => "31 CFR §501.404"
    })
  end
end
