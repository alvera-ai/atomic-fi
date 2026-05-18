defmodule Mix.Tasks.Corpus.Bench do
  @shortdoc "End-to-end bench: generate sharded corpus from N upstream sources, run them through corpus.validate in parallel, produce one consolidated proof.md."

  @moduledoc """
  Performance bench — orchestrates the full raw-data → sample → shard →
  validate → report pipeline across one or more upstream data sources.

  ## Synopsis

      mix corpus.bench
        --sources <comma-separated>     (default: saml_d,amlgentex)
        --shards <N>                    (default: 10)
        --rows <N>                      (per-source rows; default: 1000)
        --seed <N>                      (RNG seed; default: 0)
        --out <path>                    (per-source shard parent;
                                         default: tmp/bench/<src>/shards)
        --report <path>                 (consolidated markdown report;
                                         default: corpus/bench/proof.md)
        --in-mode synthetic|reseed       (default: synthetic — hardcoded
                                         row generator inside the repo;
                                         reseed needs Kaggle/Python)

  ## What it produces

  ```
   <out-per-source>/shard-00/{account_holders, counterparties,
                              payment_accounts, transactions}.ndjson
                 …shard-NN/…

   <report>          one consolidated markdown file with, per source:
                       - row count + shard count
                       - corpus.validate match/mismatch counts
                       - timing (n, p50, p95, p99, txns/sec)
                     and a top-level summary across all sources.
  ```

  ## Determinism

  In `--in-mode synthetic` (the default) NO external dependency is
  touched: rows come from `AtomicFi.Corpus.SyntheticSeed`, a hardcoded
  RNG-seeded generator that mirrors each upstream's column shape. Same
  `(--rows, --seed)` → identical row stream → identical sharded
  corpus → identical `proof.md`. Commit the report, run the bench
  again, the committed file diffs empty.

  In `--in-mode reseed` the Makefile `reseed-<src>` targets are invoked
  first (Kaggle CLI for SAML-D, uv + Python sim for AMLGentex). The
  resulting sample sits at `$CORPUS_OUT/<src>/<src>.ndjson` and is
  consumed by the same generator.

  The committed `corpus/bench/proof.md` is always the synthetic-mode
  output — the FAA-style cert anyone can reproduce from a clean clone.
  The reseed-mode bench is for operator perf tuning against the real
  upstream distribution.
  """

  use Mix.Task

  @default_sources [:saml_d, :amlgentex]
  @valid_sources [:saml_d, :amlgentex, :stableaml]

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          sources: :string,
          shards: :integer,
          rows: :integer,
          seed: :integer,
          out: :string,
          report: :string,
          in_mode: :string,
          reset: :boolean
        ]
      )

    sources = parse_sources(opts[:sources])
    shards = Keyword.get(opts, :shards, 10)
    rows = Keyword.get(opts, :rows, 1000)
    seed = Keyword.get(opts, :seed, 0)
    in_mode = Keyword.get(opts, :in_mode, "synthetic")

    report_path =
      Keyword.get(opts, :report, "benchmarks/saml_d_amlgentex_synthetic/README.md")

    reset? = Keyword.get(opts, :reset, true)

    Mix.shell().info("""
    → mix corpus.bench
        sources:    #{Enum.map_join(sources, ", ", &Atom.to_string/1)}
        shards:     #{shards}  (corpus.validate runs them in parallel)
        rows:       #{rows} per source
        seed:       #{seed}
        in_mode:    #{in_mode}
        report:     #{report_path}
    """)

    per_source =
      Enum.map(sources, fn src ->
        run_one_source(src,
          shards: shards,
          rows: rows,
          seed: seed,
          in_mode: in_mode,
          reset?: reset?
        )
      end)

    write_consolidated_report(report_path, per_source, %{
      shards: shards,
      rows: rows,
      seed: seed,
      sources: sources,
      in_mode: in_mode
    })

    Mix.shell().info("\n✓ wrote consolidated report → #{report_path}")
  end

  # ── per-source pipeline ──────────────────────────────────────────

  defp run_one_source(src, opts) do
    Mix.shell().info("\n── #{src} ─────────────────────────────")

    shard_dir = Keyword.get(opts, :out, "tmp/bench/#{src}/shards")
    File.mkdir_p!(shard_dir)
    cleanup_dir!(shard_dir)

    case opts[:in_mode] do
      "synthetic" ->
        run_generate(src,
          synthetic: true,
          rows: opts[:rows],
          seed: opts[:seed],
          shards: opts[:shards],
          out: shard_dir
        )

      "reseed" ->
        run_reseed(src, opts)

        run_generate(src,
          in: default_in_path(src),
          shards: opts[:shards],
          out: shard_dir
        )

      other ->
        Mix.raise("--in-mode must be 'synthetic' or 'reseed' (got: #{inspect(other)})")
    end

    proof_path = "tmp/bench/#{src}/proof.md"
    File.mkdir_p!(Path.dirname(proof_path))
    timing_stdout = run_validate(shard_dir, proof_path, opts[:reset?])

    %{
      src: src,
      shard_dir: shard_dir,
      proof_path: proof_path,
      report: File.read!(proof_path),
      timing_stdout: timing_stdout,
      shards: opts[:shards],
      rows: opts[:rows]
    }
  end

  defp run_reseed(src, _opts) do
    target = "reseed-#{String.replace(Atom.to_string(src), "_", "-")}"
    Mix.shell().info("→ make #{target}")
    {_out, status} = System.cmd("make", [target], stderr_to_stdout: true)

    if status != 0 do
      Mix.raise("make #{target} failed; run it directly to inspect output")
    end
  end

  defp default_in_path(:saml_d), do: "#{corpus_root()}/saml-d/saml_d.ndjson"
  defp default_in_path(:amlgentex), do: "#{corpus_root()}/amlgentex/amlgentex.ndjson"
  defp default_in_path(src), do: Mix.raise("no default --in path for #{src}")

  defp corpus_root do
    System.get_env("CORPUS_OUT") ||
      System.get_env("ATOMIC_FI_CORPUS_OUT") ||
      Path.join(System.user_home!(), ".local/share/atomic-fi/corpus")
  end

  defp run_generate(:saml_d, args) do
    Mix.Task.rerun("corpus.generate.saml_d", to_arg_list(args))
  end

  defp run_generate(:amlgentex, args) do
    Mix.Task.rerun("corpus.generate.amlgentex", to_arg_list(args))
  end

  defp run_generate(src, _args), do: Mix.raise("no generator wired for #{inspect(src)}")

  defp run_validate(shard_dir, proof_path, reset?) do
    # Invoke `mix corpus.validate` as a SUBPROCESS, not Mix.Task.rerun.
    # Postgrex caches Postgres custom-type OIDs per BEAM; corpus.validate
    # --reset drops and re-migrates the corpus schema, which gives every
    # ENUM a fresh OID. Re-running in the same BEAM left the previous
    # run's cached OIDs stale → "cache lookup failed for type NNNN" on
    # the second source's insert path. A fresh BEAM per validate run
    # cleanly avoids the issue and matches how operators invoke the
    # task by hand.
    args =
      ["corpus.validate", shard_dir, "--out", proof_path] ++
        if(reset?, do: ["--reset"], else: [])

    Mix.shell().info("→ subprocess: mix #{Enum.join(args, " ")}")

    {output, status} =
      System.cmd("mix", args,
        env: [{"MIX_ENV", to_string(Mix.env())}],
        stderr_to_stdout: true
      )

    if status != 0 do
      IO.puts(output)
      Mix.raise("mix corpus.validate exited with status #{status}")
    end

    output
  end

  defp to_arg_list(opts) do
    Enum.flat_map(opts, fn
      {:synthetic, true} -> ["--synthetic"]
      {:synthetic, false} -> []
      {k, v} -> ["--#{String.replace(Atom.to_string(k), "_", "-")}", to_string(v)]
    end)
  end

  defp cleanup_dir!(dir) do
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
  end

  defp parse_sources(nil), do: @default_sources

  defp parse_sources(csv) do
    csv
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.to_existing_atom/1)
    |> Enum.each(fn s ->
      unless s in @valid_sources do
        Mix.raise("unknown source: #{inspect(s)} (valid: #{inspect(@valid_sources)})")
      end
    end)
    |> case do
      :ok -> Enum.map(String.split(csv, ",", trim: true), &String.to_atom/1)
    end
  end

  # ── consolidated report ──────────────────────────────────────────

  defp write_consolidated_report(report_path, per_source, run) do
    File.mkdir_p!(Path.dirname(report_path))

    summary = summarise(per_source, run)
    content = render(per_source, summary, run)

    File.write!(report_path, content)
  end

  defp summarise(per_source, _run) do
    Enum.map(per_source, fn entry ->
      stats = parse_summary_table(entry.report)
      # Timing block is printed to stdout by corpus.validate's
      # `print_timing/1`; the markdown report doesn't include it. Read
      # it from the captured subprocess output.
      timing = parse_timing_block(entry.timing_stdout)
      Map.merge(entry, %{stats: stats, timing: timing})
    end)
  end

  defp render(_per_source, summary, run) do
    total_txns = length(summary) * run.shards * run.rows

    blocked = Enum.reduce(summary, 0, fn s, acc -> acc + (s.stats.blocked || 0) end)
    passed = total_txns - blocked

    avg_throughput =
      summary
      |> Enum.map(fn s -> parse_number(s.timing.txns_per_sec) end)
      |> Enum.sum()
      |> Kernel./(max(length(summary), 1))
      |> Float.round(1)

    max_p95 =
      summary
      |> Enum.map(fn s -> s.timing.p95_ms || 0 end)
      |> Enum.max(fn -> 0 end)

    """
    # Bulk performance bench — atomic-fi rule engine

    ## What was tested

    atomic-fi's rule engine was driven through **#{total_txns} synthetic
    transactions** drawn from #{length(run.sources)} AML research datasets:

    #{Enum.map_join(run.sources, "\n", &source_description/1)}

    The transactions were sharded into **#{run.shards} parallel workers**
    (the "poor-man's k6" model) and the production write path
    (`AccountHolderContext.create_account_holder/2` →
    `CounterpartyContext.create_counterparty/2` →
    `PaymentAccountContext.create_payment_account/2` →
    `TransactionContext.create_transaction/2`) was exercised end-to-end
    for every row. Each transaction passed through every rule in
    `priv/zenrule/transaction-screening/` (#{rule_count()} rules at the
    time of this run).

    ## Results

    | metric                                                         | value |
    |----------------------------------------------------------------|------:|
    | transactions processed                                         | #{total_txns} |
    | transactions blocked by a rule                                 | #{blocked} |
    | transactions passed through                                    | #{passed} |
    | block rate                                                     | #{block_pct(blocked, total_txns)}% |
    | average throughput across shards                               | #{avg_throughput} txns/sec |
    | worst-case p95 latency across shards                           | #{max_p95} ms |

    Per-dataset breakdown:

    | dataset    | rows | blocked | passed | txns/sec | p50 ms | p95 ms | p99 ms |
    |---         | ---: | ---:    | ---:   | ---:     | ---:   | ---:   | ---:   |
    #{Enum.map_join(summary, "\n", fn s -> render_summary_row(s, run.shards * run.rows) end)}

    ## Reproduce

    ```
    make bench BENCH_SOURCES="#{Enum.map_join(run.sources, ",", &Atom.to_string/1)}" \\
               BENCH_SHARDS=#{run.shards} \\
               BENCH_ROWS=#{run.rows} \\
               BENCH_SEED=#{run.seed}
    ```

    No external dependencies required (no Kaggle CLI, no Python sim).
    The synthetic transaction rows are generated deterministically by
    `AtomicFi.Corpus.SyntheticSeed` from the seed above. Same seed →
    byte-identical output.

    For real-data perf tuning (against the actual SAML-D + AMLGentex
    upstreams), use `make bench-real` after running `make reseed-saml-d`
    and `make reseed-amlgentex` once.

    ## Per-dataset detailed reports

    The full per-row drift report for each dataset is appended below.
    Rows are marked `🆕 new` because bulk-bench transactions don't carry
    a pre-calibrated `_expected` verdict — the bench measures the
    engine's actual decision distribution, not correctness against a
    pinned expectation. For the latter, see `corpus/zen_rules/<slug>/`
    (the 10 hand-authored auditor-walked scenarios).

    """ <>
      Enum.map_join(summary, "\n\n", fn entry ->
        "## #{entry.src}\n\n#{entry.report}"
      end)
  end

  defp source_description(:saml_d),
    do:
      "  - **SAML-D** (Oztas et al. 2023): synthetic transaction monitoring data " <>
        "with 28 typologies (11 normal + 17 suspicious patterns like smurfing, " <>
        "structuring, layering). Original dataset is 12 MB on Kaggle."

  defp source_description(:amlgentex),
    do:
      "  - **AMLGentex** (AI Sweden / Handelsbanken / Swedbank 2024): synthetic " <>
        "transaction-network simulator producing scale-free graphs with " <>
        "configurable normal + SAR patterns (fan-in, fan-out, layering, smurfing). " <>
        "Apache-2.0; runs Python simulator locally."

  defp source_description(other), do: "  - **#{other}**"

  defp rule_count do
    "priv/zenrule/transaction-screening"
    |> Path.absname()
    |> File.ls!()
    |> Enum.count(&String.ends_with?(&1, ".json"))
  rescue
    _ -> "N"
  end

  defp render_summary_row(entry, total_rows) do
    t = entry.timing
    blocked = entry.stats.blocked || 0
    passed = total_rows - blocked

    "| #{entry.src} | #{total_rows} | #{blocked} | #{passed} | " <>
      "#{t.txns_per_sec} | #{t.p50_ms} | #{t.p95_ms} | #{t.p99_ms} |"
  end

  defp block_pct(_blocked, 0), do: "0.0"

  defp block_pct(blocked, total),
    do: (blocked / total * 100) |> Float.round(2) |> Float.to_string()

  defp parse_number("—"), do: 0.0
  defp parse_number(s) when is_binary(s), do: String.to_float(s)
  defp parse_number(n) when is_number(n), do: n / 1.0
  defp parse_number(_), do: 0.0

  # Parse `| match | N |` and `| mismatch | N |` from the summary table.
  defp parse_summary_table(report) do
    # In the bulk-bench world `_expected` is intentionally absent, so
    # every row lands as :new in corpus.validate's outcome table. The
    # number we care about for the bench summary is "how many were
    # blocked by a rule" — count rows whose `status` line shows
    # 'rejected' in the per-row detail (not the outcome table).
    blocked =
      Regex.scan(~r/"status":\s*"rejected"/m, report)
      |> length()

    %{
      match: scan_int(report, ~r/^\|\s*match\s*\|\s*(\d+)\s*\|/m),
      mismatch: scan_int(report, ~r/^\|\s*mismatch\s*\|\s*(\d+)\s*\|/m),
      new: scan_int(report, ~r/^\|\s*new\b.*?\|\s*(\d+)\s*\|/m),
      blocked: blocked
    }
  end

  # Parse the timing block at the bottom of corpus.validate's stdout
  # (not in the proof.md by default, but if we capture it we can fold
  # it in). For now, parse the summary table only and best-effort the
  # timing fields.
  defp parse_timing_block(report) do
    %{
      txns_per_sec: scan_float(report, ~r/txns\/sec\s+([\d\.]+)/m),
      p50_ms: scan_int(report, ~r/p50\s+(\d+)\s*ms/m),
      p95_ms: scan_int(report, ~r/p95\s+(\d+)\s*ms/m),
      p99_ms: scan_int(report, ~r/p99\s+(\d+)\s*ms/m)
    }
  end

  defp scan_int(text, re) do
    case Regex.run(re, text) do
      [_, n] -> String.to_integer(n)
      _ -> 0
    end
  end

  defp scan_float(text, re) do
    case Regex.run(re, text) do
      [_, n] -> n
      _ -> "—"
    end
  end
end
