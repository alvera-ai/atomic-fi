defmodule Mix.Tasks.Corpus.Bench do
  @shortdoc "End-to-end bench: throughput sweep across concurrency levels, one consolidated GitHub-flavored markdown report."

  @moduledoc """
  Bulk performance bench. Sweeps concurrency from 1 up to `--max` in
  powers of 2, generating fresh sharded corpora and running them
  through the production write path at each level. Records per-level
  throughput + latency + block rate plus the test environment fingerprint
  (CPU model, core count, OS, runtime versions). Emits one GitHub-
  flavored markdown report.

  ## Synopsis

      mix corpus.bench
        --sources <comma>      default: saml_d,amlgentex
        --max <N>              max concurrency / shards; default 16. The
                                sweep is the powers-of-2 ladder up to N:
                                  1, 2, 4, 8, 16, 32, ...
        --rows <N>             rows per source per level; default 1000.
        --seed <N>             RNG seed for the synthetic generator; default 0.
        --report <path>        markdown out;
                                default: benchmarks/saml_d_amlgentex_synthetic/README.md
        --in-mode synthetic|reseed
                               synthetic (default) is hardcoded inside
                                AtomicFi.Corpus.SyntheticSeed — zero
                                external deps. reseed shells out to the
                                Makefile reseed-<src> targets first.

  ## Determinism

  `--in-mode synthetic` is deterministic: same `(--rows, --seed)` →
  byte-identical NDJSON → byte-identical sharded corpus.
  `corpus.validate` is non-deterministic in *timing* but every other
  field of `proof.md` is byte-stable, so re-runs diff cleanly except
  for the timing-derived columns in the throughput-sweep table.

  ## What it produces

  ```
   tmp/bench/c<level>/<src>/shards/         shard folders per level
   tmp/bench/c<level>/<src>/proof.md        per-source drift report
   <--report>                                consolidated narrative + sweep table
  ```
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
          max: :integer,
          rows: :integer,
          seed: :integer,
          report: :string,
          in_mode: :string
        ]
      )

    sources = parse_sources(opts[:sources])
    max_c = Keyword.get(opts, :max, 16)
    rows = Keyword.get(opts, :rows, 1000)
    seed = Keyword.get(opts, :seed, 0)
    in_mode = Keyword.get(opts, :in_mode, "synthetic")

    report_path =
      Keyword.get(opts, :report, "benchmarks/saml_d_amlgentex_synthetic/README.md")

    levels = power_of_two_ladder(max_c)
    env_info = collect_environment()

    Mix.shell().info("""
    → mix corpus.bench  (concurrency sweep)
        sources:        #{Enum.map_join(sources, ", ", &Atom.to_string/1)}
        levels:         #{Enum.join(levels, ", ")}
        rows/src/level: #{rows}
        seed:           #{seed}
        in_mode:        #{in_mode}
        report:         #{report_path}
    """)

    sweep_rows =
      Enum.map(levels, fn level ->
        run_level(level, sources, rows: rows, seed: seed, in_mode: in_mode)
      end)

    write_report(report_path, %{
      env: env_info,
      levels: levels,
      sweep: sweep_rows,
      sources: sources,
      rows: rows,
      seed: seed,
      in_mode: in_mode,
      max: max_c
    })

    Mix.shell().info("\n✓ wrote report → #{report_path}")
  end

  # ── concurrency sweep ────────────────────────────────────────────

  defp power_of_two_ladder(max_c) when max_c >= 1 do
    Stream.iterate(1, &(&1 * 2))
    |> Enum.take_while(&(&1 <= max_c))
  end

  defp run_level(level, sources, opts) do
    Mix.shell().info("\n── concurrency = #{level} ─────────────────────────")

    per_source =
      Enum.map(sources, fn src -> run_one_source(src, level, opts) end)

    aggregate_level(level, per_source)
  end

  defp run_one_source(src, level, opts) do
    shard_dir = "tmp/bench/c#{pad(level)}/#{src}/shards"
    proof_path = "tmp/bench/c#{pad(level)}/#{src}/proof.md"
    File.mkdir_p!(Path.dirname(proof_path))
    cleanup_dir!(shard_dir)

    case opts[:in_mode] do
      "synthetic" ->
        run_generate(src,
          synthetic: true,
          rows: opts[:rows],
          seed: opts[:seed],
          shards: level,
          out: shard_dir
        )

      "reseed" ->
        run_reseed(src)

        run_generate(src,
          in: default_in_path(src),
          shards: level,
          out: shard_dir
        )

      other ->
        Mix.raise("--in-mode must be 'synthetic' or 'reseed' (got: #{inspect(other)})")
    end

    timing_stdout = run_validate(shard_dir, proof_path)

    %{
      src: src,
      level: level,
      proof_path: proof_path,
      report: File.read!(proof_path),
      timing_stdout: timing_stdout,
      shard_dir: shard_dir
    }
  end

  # Roll the per-source numbers up to one row per concurrency level.
  defp aggregate_level(level, per_source) do
    stats = Enum.map(per_source, fn s -> parse_stats(s.report) end)
    timings = Enum.map(per_source, fn s -> parse_timing(s.timing_stdout) end)

    %{
      level: level,
      total_txns: Enum.reduce(stats, 0, &(&1.total + &2)),
      blocked: Enum.reduce(stats, 0, &(&1.blocked + &2)),
      txns_per_sec: sum_floats(timings, :txns_per_sec) |> Float.round(1),
      p50_ms: max_of(timings, :p50_ms),
      p95_ms: max_of(timings, :p95_ms),
      p99_ms: max_of(timings, :p99_ms),
      per_source: per_source
    }
  end

  defp run_reseed(src) do
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

  defp run_generate(:saml_d, args),
    do: Mix.Task.rerun("corpus.generate.saml_d", to_arg_list(args))

  defp run_generate(:amlgentex, args),
    do: Mix.Task.rerun("corpus.generate.amlgentex", to_arg_list(args))

  defp run_generate(src, _args), do: Mix.raise("no generator wired for #{inspect(src)}")

  defp run_validate(shard_dir, proof_path) do
    # SUBPROCESS — Postgrex caches Postgres custom-type OIDs per BEAM;
    # corpus.validate --reset drops + re-migrates the corpus schema,
    # which gives every enum a fresh OID. Fresh BEAM per validate run
    # cleanly avoids the type-cache lookup failure on the second run.
    args = ["corpus.validate", shard_dir, "--out", proof_path, "--reset"]
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
    parsed =
      csv
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.to_atom/1)

    Enum.each(parsed, fn s ->
      unless s in @valid_sources do
        Mix.raise("unknown source: #{inspect(s)} (valid: #{inspect(@valid_sources)})")
      end
    end)

    parsed
  end

  # ── environment fingerprint ──────────────────────────────────────

  defp collect_environment do
    %{
      run_date: DateTime.utc_now() |> DateTime.truncate(:second),
      cpu_brand: cpu_brand(),
      cpu_cores: cpu_cores(),
      os_kernel: os_kernel(),
      elixir_version: System.version(),
      otp_version: System.otp_release(),
      postgres_version: shell_capture("psql", ["--version"]),
      zenrule_version: zenrule_version(),
      rule_count: rule_count()
    }
  end

  defp cpu_brand do
    case :os.type() do
      {:unix, :darwin} -> shell_capture("sysctl", ["-n", "machdep.cpu.brand_string"])
      {:unix, _} -> shell_grep("/proc/cpuinfo", ~r/^model name\s*:\s*(.+)$/m)
      _ -> "—"
    end
  end

  defp cpu_cores do
    case :os.type() do
      {:unix, :darwin} -> shell_capture("sysctl", ["-n", "hw.ncpu"])
      {:unix, _} -> shell_capture("nproc", [])
      _ -> "—"
    end
  end

  defp os_kernel do
    "#{shell_capture("uname", ["-s"])} #{shell_capture("uname", ["-r"])} #{shell_capture("uname", ["-m"])}"
  end

  defp zenrule_version do
    case System.cmd("curl", ["-fsSL", "http://localhost:8090/api/version"],
           stderr_to_stdout: true
         ) do
      {output, 0} -> String.trim(output)
      _ -> "—"
    end
  rescue
    _ -> "—"
  end

  defp shell_capture(cmd, args) do
    case System.cmd(cmd, args, stderr_to_stdout: true) do
      {output, 0} -> output |> String.trim()
      _ -> "—"
    end
  rescue
    _ -> "—"
  end

  defp shell_grep(path, re) do
    case File.read(path) do
      {:ok, content} ->
        case Regex.run(re, content) do
          [_, brand] -> String.trim(brand)
          _ -> "—"
        end

      _ ->
        "—"
    end
  end

  defp rule_count do
    "priv/zenrule/transaction-screening"
    |> Path.absname()
    |> File.ls!()
    |> Enum.count(&String.ends_with?(&1, ".json"))
  rescue
    _ -> 0
  end

  # ── stats parsing ────────────────────────────────────────────────

  defp parse_stats(report) do
    blocked = Regex.scan(~r/"status":\s*"rejected"/m, report) |> length()
    total = scan_int(report, ~r/^\|\s*\*\*total\*\*\s*\|\s*\*\*(\d+)\*\*/m)

    %{
      total: total,
      blocked: blocked,
      new: scan_int(report, ~r/^\|\s*new\b.*?\|\s*(\d+)\s*\|/m)
    }
  end

  defp parse_timing(report) do
    %{
      txns_per_sec: scan_float(report, ~r/txns\/sec\s+([\d\.]+)/m),
      p50_ms: scan_int(report, ~r/p50\s+(\d+)\s*ms/m),
      p95_ms: scan_int(report, ~r/p95\s+(\d+)\s*ms/m),
      p99_ms: scan_int(report, ~r/p99\s+(\d+)\s*ms/m)
    }
  end

  defp sum_floats(items, key) do
    Enum.reduce(items, 0.0, fn item, acc -> acc + (Map.get(item, key) || 0.0) end)
  end

  defp max_of(items, key) do
    items |> Enum.map(&Map.get(&1, key, 0)) |> Enum.max(fn -> 0 end)
  end

  defp scan_int(text, re) do
    case Regex.run(re, text) do
      [_, n] -> String.to_integer(n)
      _ -> 0
    end
  end

  defp scan_float(text, re) do
    case Regex.run(re, text) do
      [_, n] -> String.to_float(n)
      _ -> 0.0
    end
  end

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(3, "0")

  # ── render ───────────────────────────────────────────────────────

  defp write_report(path, run) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, render(run))
  end

  defp render(run) do
    """
    # Bulk performance bench — atomic-fi rule engine

    > Concurrency sweep across powers of 2, from 1 up to **#{run.max}**.
    > Every transaction is driven end-to-end through the production
    > write path and the full rule engine (#{run.env.rule_count} rules
    > under `priv/zenrule/transaction-screening/`).

    ## Test environment

    | component | value |
    |---|---|
    | run date          | `#{DateTime.to_iso8601(run.env.run_date)}` |
    | CPU               | #{run.env.cpu_brand} |
    | CPU cores         | #{run.env.cpu_cores} |
    | OS / kernel       | #{run.env.os_kernel} |
    | Elixir            | #{run.env.elixir_version} |
    | Erlang / OTP      | #{run.env.otp_version} |
    | Postgres          | #{run.env.postgres_version} |
    | ZenRule (agent)   | `#{run.env.zenrule_version}` |
    | rule count        | #{run.env.rule_count} |

    ## What was tested

    For each concurrency level in the sweep, atomic-fi processed
    **#{run.rows} synthetic transactions per source** drawn from the AML
    research datasets below. Each transaction went through:

    1. `AccountHolderContext.create_account_holder/2`
    2. `CounterpartyContext.create_counterparty/2`
    3. `PaymentAccountContext.create_payment_account/2`
    4. `TransactionContext.create_transaction/2` → rule engine fan-out
       → ledger entry posting

    The rule engine fans out N parallel `RuleEngine.Default.evaluate/4`
    calls to the GoRules ZenRule agent (one per rule under
    `transaction-screening/`) and folds the per-rule outputs into a
    single effective control per ledger account.

    ### Sources

    #{Enum.map_join(run.sources, "\n", &source_description/1)}

    ## Throughput sweep

    | concurrency | total txns | blocked | passed | txns/sec | p50 (ms) | p95 (ms) | p99 (ms) |
    | ---:        | ---:       | ---:    | ---:   | ---:     | ---:     | ---:     | ---:     |
    #{Enum.map_join(run.sweep, "\n", &render_sweep_row/1)}

    ## Reproduce

    ```
    make bench BENCH_MAX=#{run.max} BENCH_ROWS=#{run.rows} BENCH_SEED=#{run.seed}
    ```

    Synthetic mode requires no external dependencies — rows are
    generated by `AtomicFi.Corpus.SyntheticSeed` from a fixed RNG seed.
    Same seed → identical NDJSON → identical sharded corpus. Timing
    columns vary across runs (they're real wall-clock measurements);
    every other column diffs cleanly.

    For real-data perf tuning (the actual SAML-D dataset from Kaggle
    and the AMLGentex Python simulator's output), run
    `make bench-real` after `make reseed-saml-d` and
    `make reseed-amlgentex` once. The report lands under `tmp/` to
    keep the committed cert deterministic.

    <details><summary>Per-concurrency detailed reports (per-row drift, full timing)</summary>

    #{Enum.map_join(run.sweep, "\n\n", &render_level_detail/1)}

    </details>

    ## How this report is generated

    `mix corpus.bench` orchestrates the whole pipeline:

    1. Collects the test environment fingerprint (CPU, OS, runtime versions).
    2. For each concurrency level in the power-of-2 ladder:
        - regenerates a fresh sharded corpus per source via
          `mix corpus.generate.<src>`;
        - invokes `mix corpus.validate <shards> --reset` as a subprocess
          (fresh BEAM per validate run — Postgrex caches custom-type
          OIDs per process, and `--reset` invalidates them);
        - captures the per-source `proof.md` plus the timing block
          (printed to stdout, parsed by regex into the sweep row).
    3. Renders the consolidated markdown — this file.

    See `lib/mix/tasks/corpus.bench.ex` for the implementation.
    """
  end

  defp source_description(:saml_d),
    do:
      "- **SAML-D** (Oztas et al. 2023): synthetic transaction monitoring data " <>
        "with 28 typologies — 11 normal and 17 suspicious patterns including " <>
        "smurfing, structuring, layering. " <>
        "Real Kaggle dataset: 12 MB / ~9.5 M rows. " <>
        "[paper](https://ieeexplore.ieee.org/document/10374100), " <>
        "[dataset](https://www.kaggle.com/datasets/berkanoztas/synthetic-transaction-monitoring-dataset-aml)"

  defp source_description(:amlgentex),
    do:
      "- **AMLGentex** (AI Sweden / Handelsbanken / Swedbank 2024): scale-free " <>
        "transaction-network simulator with configurable normal and SAR patterns " <>
        "(fan-in, fan-out, layering, smurfing). Apache-2.0. " <>
        "[paper](https://arxiv.org/abs/2506.13989), " <>
        "[repo](https://github.com/aidotse/AMLGentex)"

  defp source_description(other), do: "- **#{other}**"

  defp render_sweep_row(level) do
    "| #{level.level} | #{level.total_txns} | #{level.blocked} | " <>
      "#{level.total_txns - level.blocked} | #{level.txns_per_sec} | " <>
      "#{level.p50_ms} | #{level.p95_ms} | #{level.p99_ms} |"
  end

  defp render_level_detail(level) do
    blocks =
      Enum.map_join(level.per_source, "\n\n", fn s ->
        "#### #{s.src} (concurrency #{s.level})\n\n#{s.report}"
      end)

    """
    ### Concurrency #{level.level}

    Total: #{level.total_txns} txns ¦ blocked: #{level.blocked} ¦ throughput: #{level.txns_per_sec} txns/sec ¦ p95: #{level.p95_ms} ms

    #{blocks}
    """
  end
end
