defmodule Mix.Tasks.Corpus.Bench do
  @shortdoc "End-to-end bench: k6-shape VU sweep across the 10 catalog scenarios, one consolidated GitHub-flavored markdown report."

  @moduledoc """
  Bulk performance bench, k6-shape. Each VU is one parallel
  iteration of a catalog scenario from `corpus/zen_rules/<slug>/`:
  insert AH/CP/BO/PA, then create the scenario's transactions
  (sequential within the VU — velocity rules depend on arrival
  order). Across VUs, scenarios are picked round-robin and every
  VU gets a fresh UUID-prefixed external_id namespace so the DB
  never sees a clash.

  Architecture A (in-process Tasks):
   - One BEAM, one Repo pool, one rule-engine HTTP client.
   - Schema is reset once at bench start (not per-VU).
   - Each level N spawns `Task.async_stream(0..N-1, …)`.
   - Per-VU results are folded into one row per concurrency level.

  ## Synopsis

      mix corpus.bench
        --levels <csv>         VU ladder; default 1,10,100,1000,2000,10000.
                                Example: --levels 1,10,100
        --report <path>        markdown out; default auto-named under
                                benchmarks/ as
                                <cpu-slug>-<yyyy-mm-dd>-<peak-vus-english>-vus.md
        --scenarios <dir>      root holding the catalog scenarios;
                                default corpus/zen_rules/

  Engine_error transients under load are tolerated (counted in a column,
  not a sweep-aborter). Mismatch and setup_error are correctness breaks
  — they abort the sweep with non-zero exit.
  """

  use Mix.Task

  alias AtomicFi.Corpus.ScenarioRunner

  @default_levels [1, 10, 100, 1000, 2000, 10000]
  @scenario_slugs ~w(
    de_minimis_stablecoin
    cip_kyc_gate
    ofac_sdn_match
    ctr_structuring
    smurfing_pattern_sar_eligible
    prohibited_risk_freeze
    ah_country_kp_residence
    business_ah_zero_bos
    internal_blocklist_lastname
    stableaml_wallet_blocklist
  )

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [levels: :string, report: :string, scenarios: :string]
      )

    levels = parse_levels(opts[:levels])
    scenarios_root = Keyword.get(opts, :scenarios, "corpus/zen_rules")
    env_info = collect_environment()

    report_path =
      case Keyword.get(opts, :report) do
        nil -> auto_report_path("benchmarks", env_info, Enum.max(levels))
        explicit -> explicit
      end

    Mix.shell().info("""
    → mix corpus.bench  (k6-shape VU sweep)
        scenarios root: #{scenarios_root}
        scenarios:      #{length(@scenario_slugs)} (#{Enum.join(@scenario_slugs, ", ")})
        VU ladder:      #{Enum.join(levels, ", ")}
        report:         #{report_path}
    """)

    ScenarioRunner.inject_search_path_after_connect!()
    Mix.Task.run("app.start")

    ScenarioRunner.ensure_schema!(true)

    session = ScenarioRunner.build_system_session()

    scenarios =
      @scenario_slugs
      |> Enum.map(&Path.join(scenarios_root, &1))
      |> Enum.map(&ScenarioRunner.load_scenario/1)

    ScenarioRunner.seed_blocklists!(session, scenarios, verbose: false)

    # Trap linked-process EXITs so a saturated DB pool / rule-engine
    # client dying mid-level doesn't take down the bench process before
    # the report is written.
    Process.flag(:trap_exit, true)

    # Write the report progressively after each level — at high VU counts
    # a level can take long enough that the operator wants to peek mid-
    # sweep, and a parent crash on the FINAL level should not lose the
    # earlier rows.
    sweep_rows =
      levels
      |> Enum.reduce([], fn level, acc ->
        row =
          try do
            run_level(session, scenarios, level)
          rescue
            err ->
              Mix.shell().error("⚠ VU level #{level} aborted: #{Exception.message(err)}")

              level_aborted(level, err)
          catch
            kind, reason ->
              Mix.shell().error("⚠ VU level #{level} caught #{kind}: #{inspect(reason)}")
              level_aborted(level, {kind, reason})
          end

        new_acc = acc ++ [row]

        write_report(report_path, %{
          env: env_info,
          levels: levels,
          sweep: new_acc,
          scenarios: @scenario_slugs,
          scenarios_root: scenarios_root
        })

        Mix.shell().info(
          "✓ incremental report → #{report_path} (#{length(new_acc)}/#{length(levels)} levels)"
        )

        new_acc
      end)

    Mix.shell().info("\n✓ wrote report → #{report_path}")

    if Enum.any?(sweep_rows, &(&1.mismatches > 0 or &1.setup_errors > 0)) do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end

  # ── VU sweep ─────────────────────────────────────────────────────

  defp run_level(session, scenarios, level) do
    Mix.shell().info("\n── VUs = #{level} ─────────────────────────")

    n_scenarios = length(scenarios)

    wall_t0 = System.monotonic_time(:millisecond)

    results =
      0..(level - 1)
      |> Task.async_stream(
        fn vu_idx ->
          scenario = Enum.at(scenarios, rem(vu_idx, n_scenarios))
          # Per-VU UUID prefix: keeps every VU's external_id namespace
          # disjoint at the DB layer, even when two VUs share a scenario.
          prefix = "vu-" <> Ecto.UUID.generate() <> "-"

          try do
            {rows, _prefix} =
              ScenarioRunner.run_vu(session, scenario, prefix: prefix, verbose: false)

            {:ok, scenario.path, rows}
          rescue
            err ->
              {:vu_crash, scenario.path, err, __STACKTRACE__}
          end
        end,
        max_concurrency: level,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.to_list()

    wall_ms = System.monotonic_time(:millisecond) - wall_t0

    aggregate_level(level, results, wall_ms)
  end

  # Synthetic row for a level that crashed at the parent supervisor — the
  # report still gets a placeholder so the operator sees where the sweep
  # broke and can re-run with a smaller --levels list or a bigger pool.
  defp level_aborted(level, err) do
    %{
      level: level,
      vus: level,
      wall_ms: 0,
      total_txns: 0,
      matches: 0,
      new: 0,
      blocked: 0,
      mismatches: 0,
      setup_errors: 0,
      engine_errors: 0,
      vu_crashes: 0,
      crashes: [{:level_aborted, err, []}],
      txns_per_sec: 0.0,
      p50_ms: 0,
      p95_ms: 0,
      p99_ms: 0
    }
  end

  defp aggregate_level(level, results, wall_ms) do
    {rows, crashes} =
      Enum.reduce(results, {[], []}, fn
        {:ok, {:ok, _path, rows}}, {acc_rows, acc_crashes} ->
          {acc_rows ++ rows, acc_crashes}

        {:ok, {:vu_crash, path, err, stacktrace}}, {acc_rows, acc_crashes} ->
          {acc_rows, [{path, err, stacktrace} | acc_crashes]}

        {:exit, reason}, {acc_rows, acc_crashes} ->
          {acc_rows, [{:task_exit, reason, []} | acc_crashes]}
      end)

    total = length(rows)

    counts = Enum.frequencies_by(rows, & &1.status)
    matches = Map.get(counts, :match, 0)
    new_rows = Map.get(counts, :new, 0)
    mismatches = Map.get(counts, :mismatch, 0)
    setup_errors = Map.get(counts, :setup_error, 0)
    engine_errors = Map.get(counts, :engine_error, 0)

    blocked =
      Enum.count(rows, fn r ->
        is_map(r.actual) and Map.get(r.actual, "status") == "rejected"
      end)

    samples = rows |> Enum.map(& &1.elapsed_ms) |> Enum.reject(&is_nil/1) |> Enum.sort()
    txns_per_sec = if wall_ms > 0, do: Float.round(total * 1_000 / wall_ms, 1), else: 0.0

    %{
      level: level,
      vus: level,
      wall_ms: wall_ms,
      total_txns: total,
      matches: matches,
      new: new_rows,
      blocked: blocked,
      mismatches: mismatches,
      setup_errors: setup_errors,
      engine_errors: engine_errors,
      vu_crashes: length(crashes),
      crashes: crashes,
      txns_per_sec: txns_per_sec,
      p50_ms: percentile(samples, 0.50),
      p95_ms: percentile(samples, 0.95),
      p99_ms: percentile(samples, 0.99)
    }
  end

  defp percentile([], _p), do: 0

  defp percentile(sorted, p) do
    len = length(sorted)
    idx = max(0, min(len - 1, round(p * (len - 1))))
    Enum.at(sorted, idx)
  end

  # ── flags ────────────────────────────────────────────────────────

  defp parse_levels(nil), do: @default_levels

  defp parse_levels(csv) do
    csv
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.to_integer/1)
    |> Enum.filter(&(&1 > 0))
    |> case do
      [] -> Mix.raise("--levels must contain at least one positive integer")
      levels -> levels
    end
  end

  # ── environment fingerprint ──────────────────────────────────────

  defp collect_environment do
    %{
      run_date: DateTime.utc_now() |> DateTime.truncate(:second),
      cpu_brand: cpu_brand(),
      cpu_cores: cpu_cores(),
      load_avg_pre_test: load_avg(),
      os_kernel: os_kernel(),
      elixir_version: System.version(),
      otp_version: System.otp_release(),
      postgres_version: shell_capture("psql", ["--version"]),
      zenrule_version: zenrule_version(),
      rule_count: rule_count(),
      db_pool_size: db_pool_size()
    }
  end

  defp db_pool_size do
    case Application.get_env(:atomic_fi, AtomicFi.Repo, [])[:pool_size] do
      n when is_integer(n) -> Integer.to_string(n)
      _ -> "—"
    end
  end

  defp load_avg do
    case :os.type() do
      {:unix, :darwin} ->
        case System.cmd("sysctl", ["-n", "vm.loadavg"], stderr_to_stdout: true) do
          {output, 0} ->
            output
            |> String.trim()
            |> String.replace(~r/^\{\s*|\s*\}$/, "")
            |> String.replace(~r/\s+/, " ")

          _ ->
            "—"
        end

      {:unix, _} ->
        shell_grep("/proc/loadavg", ~r/^([\d\.]+\s+[\d\.]+\s+[\d\.]+)/)

      _ ->
        "—"
    end
  end

  defp auto_report_path(dir, env, peak_vus) do
    cpu_slug =
      env.cpu_brand
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> case do
        "" -> "unknown-cpu"
        s -> s
      end

    date = Date.utc_today() |> Date.to_iso8601()
    vus_english = english_count(peak_vus)
    Path.join(dir, "#{cpu_slug}-#{date}-#{vus_english}-vus.md")
  end

  defp english_count(1), do: "one"
  defp english_count(10), do: "ten"
  defp english_count(100), do: "one-hundred"
  defp english_count(500), do: "five-hundred"
  defp english_count(1_000), do: "one-thousand"
  defp english_count(2_000), do: "two-thousand"
  defp english_count(5_000), do: "five-thousand"
  defp english_count(10_000), do: "ten-thousand"
  defp english_count(20_000), do: "twenty-thousand"
  defp english_count(50_000), do: "fifty-thousand"
  defp english_count(100_000), do: "one-hundred-thousand"
  defp english_count(1_000_000), do: "one-million"
  defp english_count(n), do: Integer.to_string(n)

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

  # ── render ───────────────────────────────────────────────────────

  defp write_report(path, run) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, render(run))
  end

  defp render(run) do
    """
    # Bulk performance bench — atomic-fi rule engine

    > k6-shape VU sweep. Each VU is one parallel iteration of a
    > catalog scenario (round-robin across the #{length(run.scenarios)} scenarios
    > under `#{run.scenarios_root}/`). Within a VU the transactions run
    > sequentially (velocity rules need arrival order); across VUs the
    > runs are independent (each VU has a UUID-prefixed external_id
    > namespace, no cross-VU sharing).

    ## Test environment

    | component | value |
    |---|---|
    | run date          | `#{DateTime.to_iso8601(run.env.run_date)}` |
    | CPU               | #{run.env.cpu_brand} |
    | CPU cores         | #{run.env.cpu_cores} |
    | load average pre-test (1m / 5m / 15m) | `#{run.env.load_avg_pre_test}` |
    | OS / kernel       | #{run.env.os_kernel} |
    | Elixir            | #{run.env.elixir_version} |
    | Erlang / OTP      | #{run.env.otp_version} |
    | Postgres          | #{run.env.postgres_version} |
    | ZenRule (agent)   | `#{run.env.zenrule_version}` |
    | rule count        | #{run.env.rule_count} |
    | DB pool size      | #{run.env.db_pool_size} |
    | VU ladder         | #{Enum.join(run.levels, ", ")} |

    ## Rules under test (#{run.env.rule_count})

    Every transaction in this run was evaluated against all
    `priv/zenrule/transaction-screening/` rules in parallel; the
    per-rule outputs were folded into one effective control per
    ledger account before the transaction was either accepted or
    rejected with a `rejected_rule`.

    #{rules_under_test_table()}

    ## Catalog scenarios (#{length(run.scenarios)})

    Each VU is one parallel iteration of one of these scenarios. Mix of
    happy-path, BSA/OFAC blocks, CIP gates, and stablecoin/sanctions
    flows — the full live-platform surface, not a synthetic micro-bench.

    #{Enum.map_join(run.scenarios, "\n", &"- `#{&1}`")}

    ## VU sweep

    | VUs | wall (ms) | txns | matches | blocked | mismatches | setup err | engine err | crashes | txns/sec | p50 (ms) | p95 (ms) | p99 (ms) |
    | ---:| ---:      | ---: | ---:    | ---:    | ---:       | ---:      | ---:       | ---:    | ---:     | ---:     | ---:     | ---:     |
    #{Enum.map_join(run.sweep, "\n", &render_sweep_row/1)}

    #{Enum.map_join(run.sweep, "\n\n", &render_level_section/1)}

    ## Reproduce

    ```
    make bench BENCH_LEVELS=#{Enum.join(run.levels, ",")}
    ```

    ## How this report is generated

    `mix corpus.bench` runs the whole sweep in one BEAM:

    1. Collects the test environment fingerprint.
    2. Drops + remigrates the `atomic_fi_corpus` Postgres schema
       ONCE at the start (not per-VU — fresh schema gives every enum
       a fresh Postgrex type OID; one reset per BEAM is enough).
    3. Loads the 10 catalog scenarios from
       `corpus/zen_rules/<slug>/` into memory, seeds their union of
       blocklist entries once.
    4. For each VU level N, spawns `Task.async_stream(0..N-1, …)`
       — each task picks a scenario round-robin, generates a fresh
       UUID id-prefix, and runs the scenario's full insert + txn
       pipeline serially within the task.
    5. Folds per-VU results into one row per level + writes this report.

    See `lib/mix/tasks/corpus.bench.ex` and
    `lib/atomic_fi/corpus/scenario_runner.ex`.
    """
  end

  defp render_sweep_row(level) do
    "| #{level.vus} | #{level.wall_ms} | #{level.total_txns} | #{level.matches} | " <>
      "#{level.blocked} | #{level.mismatches} | #{level.setup_errors} | " <>
      "#{level.engine_errors} | #{level.vu_crashes} | #{level.txns_per_sec} | " <>
      "#{level.p50_ms} | #{level.p95_ms} | #{level.p99_ms} |"
  end

  defp render_level_section(level) do
    crashes_block =
      if level.vu_crashes > 0 do
        sample = Enum.take(level.crashes, 3)

        bullets =
          Enum.map_join(sample, "\n", fn
            {path, %{message: msg}, _st} -> "- `#{path}`: #{msg}"
            {path, err, _st} -> "- `#{path}`: #{inspect(err) |> String.slice(0, 200)}"
          end)

        "\n\n**VU crashes (#{level.vu_crashes} total, first #{length(sample)} shown):**\n\n#{bullets}"
      else
        ""
      end

    """
    ## VUs #{level.vus}

    Wall: #{level.wall_ms} ms · txns: #{level.total_txns} · throughput: #{level.txns_per_sec} txns/sec
    · matches: #{level.matches} · blocked: #{level.blocked} · mismatches: #{level.mismatches}
    · setup_errors: #{level.setup_errors} · engine_errors: #{level.engine_errors} · vu_crashes: #{level.vu_crashes}
    · p50 #{level.p50_ms} ms · p95 #{level.p95_ms} ms · p99 #{level.p99_ms} ms#{crashes_block}
    """
  end

  defp rules_under_test_table do
    rows = [
      {"de_minimis_stablecoin", "31 CFR §1020.220",
       "creditor_payment_account.account_holder.kyc_status"},
      {"cip_kyc_gate", "BSA §326 (31 CFR §1020.220)", "account_holder.kyc_status"},
      {"ofac_sdn_match", "OFAC 31 CFR §501.404; §501.603",
       "creditor_payment_account.compliance_screenings[].sanctions_matches[]"},
      {"ctr_structuring", "BSA §5324; 31 CFR §1020.320",
       "account_holder.recent_debits_24h[] (sub-CTR amount band)"},
      {"smurfing_pattern_sar_eligible", "BSA §5324; 31 CFR §1020.320",
       "account_holder.recent_debits_24h[] (≥6 distinct creditor PAs ≤ smurf_max)"},
      {"prohibited_risk_freeze", "Internal policy; 31 CFR §1010.230",
       "account_holder.risk_level"},
      {"ah_country_kp_residence", "OFAC E.O. 13466 (KP); IR/CU/SY sets",
       "account_holder.legal_entity.addresses[] primary residential country"},
      {"business_ah_zero_bos", "Corporate Transparency Act; 31 CFR §1010.380",
       "account_holder.account_holder_type + beneficial_owners[]"},
      {"internal_blocklist_lastname", "FFIEC BSA/AML Examination Manual",
       "creditor_payment_account.compliance_screenings[].blocklist_matches[]"},
      {"stableaml_wallet_blocklist", "OFAC 31 CFR §501.404; GENIUS Act §4(a)(5)",
       "creditor_payment_account.wallet_address"}
    ]

    header = "| rule | regulatory cite | payload field read |\n|---|---|---|"

    body =
      Enum.map_join(rows, "\n", fn {name, cite, reads} ->
        "| `#{name}` | #{cite} | `#{reads}` |"
      end)

    header <> "\n" <> body
  end
end
