defmodule Mix.Tasks.Corpus.Validate do
  @shortdoc "Replays a corpus folder against the live atomic-fi write path and prints a markdown drift report"

  @moduledoc """
  Walks a corpus folder of NDJSON files, inserts the entity graph through the
  production contexts, then creates each transaction and diffs the resulting
  `%Transaction{}` state against the row's inline `_expected` block.

  Corpus folder layout:

      corpus/<group>/<corpus_slug>/
        account_holders.ndjson
        counterparties.ndjson
        payment_accounts.ndjson
        transactions.ndjson

  Usage:

      $ mix corpus.validate                                        # all scenarios under corpus/zen_rules/
      $ mix corpus.validate corpus/zen_rules/de_minimis_stablecoin  # single scenario
      $ mix corpus.validate corpus/zen_rules/de_minimis_stablecoin --out tmp/report.md
      $ mix corpus.validate corpus/zen_rules/de_minimis_stablecoin --reset
      $ mix corpus.validate corpus/zen_rules/de_minimis_stablecoin --concurrency 8

  `--concurrency K` repeats the scenario K times sequentially, each
  with its own `vu####-` id prefix. Useful for volume testing.

  Always runs inside a dedicated Postgres schema (`atomic_fi_corpus`).
  Requires the backing services up (`make run-backing-services`).
  """

  use Mix.Task

  alias AtomicFi.Corpus.ScenarioRunner

  @impl true
  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [out: :string, reset: :boolean, concurrency: :integer]
      )

    corpus_path = List.first(positional)

    ScenarioRunner.inject_search_path_after_connect!()
    Mix.Task.run("app.start")
    ScenarioRunner.ensure_schema!(opts[:reset])

    session = ScenarioRunner.build_system_session()

    scenario_paths = discover_scenarios(corpus_path)

    all_rows =
      Enum.flat_map(scenario_paths, fn path ->
        Mix.shell().info("─── #{Path.basename(path)} ───")
        run_single_scenario(session, path, opts)
      end)

    report = render_markdown(corpus_path || "corpus/zen_rules", all_rows)

    case opts[:out] do
      nil ->
        IO.write(report)

      path ->
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, report)
        Mix.shell().info("✓ Wrote validation report to #{path}")
    end

    all_timings = Enum.reject(all_rows, &is_nil(&1.elapsed_ms))
    print_timing(all_timings)

    if Enum.any?(all_rows, &(&1.status in [:mismatch, :engine_error, :setup_error])) do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end

  # ── scenario discovery ─────────────────────────────────────────────

  @default_catalog "corpus/zen_rules"

  defp discover_scenarios(nil) do
    discover_scenarios(@default_catalog)
  end

  defp discover_scenarios(path) do
    cond do
      has_ndjson?(path) ->
        [path]

      has_shards?(path) ->
        path
        |> File.ls!()
        |> Enum.filter(&String.starts_with?(&1, "shard-"))
        |> Enum.map(&Path.join(path, &1))
        |> Enum.filter(&File.dir?/1)
        |> Enum.sort()

      File.dir?(path) ->
        path
        |> File.ls!()
        |> Enum.map(&Path.join(path, &1))
        |> Enum.filter(&(File.dir?(&1) and has_ndjson?(&1)))
        |> Enum.sort()

      true ->
        Mix.raise("corpus folder not found: #{path}")
    end
  end

  defp has_ndjson?(dir) do
    File.exists?(Path.join(dir, "transactions.ndjson"))
  end

  defp has_shards?(dir) do
    case File.ls(dir) do
      {:ok, entries} -> Enum.any?(entries, &String.starts_with?(&1, "shard-"))
      _ -> false
    end
  end

  # ── single scenario execution ────────────────────────────────────

  defp run_single_scenario(session, path, opts) do
    scenario = ScenarioRunner.load_scenario(path)
    ScenarioRunner.seed_blocklists!(session, [scenario])

    concurrency = Keyword.get(opts, :concurrency, 1)

    vu_outputs = run_vus(session, scenario, concurrency)
    reduce_vu_outputs(vu_outputs)
  end

  # ── VU fan-out ────────────────────────────────────────────────────

  defp run_vus(session, scenario, concurrency) do
    Enum.map(0..(concurrency - 1), fn vu ->
      prefix = vu_prefix(vu)
      {rows, _prefix} = ScenarioRunner.run_vu(session, scenario, prefix: prefix, verbose: true)
      rows
    end)
  end

  defp vu_prefix(vu), do: "vu#{:io_lib.format("~4..0B", [vu]) |> IO.iodata_to_binary()}-"

  # ── reduce + render ───────────────────────────────────────────────

  defp reduce_vu_outputs([vu0 | rest_vus]) do
    Enum.with_index(vu0)
    |> Enum.map(fn {row, idx} ->
      others = Enum.map(rest_vus, &Enum.at(&1, idx))
      reduce_row(row, others)
    end)
  end

  defp reduce_row(canonical, []), do: canonical

  defp reduce_row(canonical, others) do
    if Enum.all?(others, &(&1.actual == canonical.actual and &1.status == canonical.status)) do
      canonical
    else
      diverging = Enum.find(others, &(&1.actual != canonical.actual))

      %{
        canonical
        | status: :mismatch,
          expected: canonical.actual,
          actual: diverging && diverging.actual
      }
    end
  end

  defp render_markdown(corpus_path, rows) do
    header = """
    # corpus.validate report

    - corpus: `#{corpus_path}`
    - transactions: #{length(rows)}

    """

    details =
      if rows == [] do
        "_No transactions in this corpus._\n\n"
      else
        Enum.map_join(rows, "\n", &render_row/1)
      end

    summary = render_summary(rows)

    header <> details <> "\n" <> summary
  end

  defp render_row(%{status: status, external_id: ext_id, label: label} = row) do
    """
    ## #{ext_id}

    - status:   **#{status_label(status)}**
    - regime:   #{Map.get(label, "regime", "—")}
    - cite:     #{Map.get(label, "cite", "—")}
    - scenario: #{Map.get(label, "scenario", "—")}

    #{render_body(row)}
    """
  end

  defp render_body(%{status: :setup_error, error: errors}) do
    "```text\nsetup_error (changeset): #{inspect(errors)}\n```\n"
  end

  defp render_body(%{status: :engine_error, error: reason}) do
    "```text\nengine_error: #{inspect(reason)}\n```\n"
  end

  defp render_body(%{status: :new, actual: actual}) do
    """
    <details open><summary>actual (no _expected on row)</summary>

    ```json
    #{Jason.encode!(actual, pretty: true)}
    ```
    </details>
    """
  end

  defp render_body(%{status: :match, actual: actual}) do
    """
    <details><summary>response (matches expected)</summary>

    ```json
    #{Jason.encode!(actual, pretty: true)}
    ```
    </details>
    """
  end

  defp render_body(%{status: :mismatch, actual: actual, expected: expected}) do
    """
    <details open><summary>diff</summary>

    ```diff
    - expected: #{Jason.encode!(expected)}
    + actual:   #{Jason.encode!(actual)}
    ```
    </details>
    """
  end

  defp render_summary(rows) do
    counts = Enum.frequencies_by(rows, & &1.status)

    """
    ## Summary

    | status | count |
    |---|---|
    | match | #{Map.get(counts, :match, 0)} |
    | new (no _expected) | #{Map.get(counts, :new, 0)} |
    | mismatch | #{Map.get(counts, :mismatch, 0)} |
    | setup_error | #{Map.get(counts, :setup_error, 0)} |
    | engine_error | #{Map.get(counts, :engine_error, 0)} |
    | **total** | **#{length(rows)}** |
    """
  end

  defp print_timing(rows) do
    samples = rows |> Enum.map(& &1.elapsed_ms) |> Enum.reject(&is_nil/1) |> Enum.sort()

    case samples do
      [] ->
        Mix.shell().error("Timing: (no rows timed)")

      _ ->
        total = Enum.sum(samples)
        n = length(samples)
        avg = total / n
        rate = if total > 0, do: n * 1_000 / total, else: 0.0

        Mix.shell().error("""

        Timing (poor man's k6 — per-row TransactionContext.create_transaction)
          n         #{n}
          ms_total  #{total}
          ms_avg    #{format_ms_float(avg)}
          txns/sec  #{format_rate(rate)}
          p50       #{percentile(samples, 0.50)} ms
          p95       #{percentile(samples, 0.95)} ms
          p99       #{percentile(samples, 0.99)} ms
          ms_max    #{List.last(samples)}
        """)
    end
  end

  defp percentile(sorted, p) when is_list(sorted) and is_float(p) do
    len = length(sorted)
    idx = max(0, min(len - 1, round(p * (len - 1))))
    Enum.at(sorted, idx)
  end

  defp format_ms_float(ms), do: :erlang.float_to_binary(ms / 1, decimals: 1)
  defp format_rate(rate), do: :erlang.float_to_binary(rate / 1, decimals: 1)

  defp status_label(:match), do: "✓ match"
  defp status_label(:new), do: "🆕 new"
  defp status_label(:mismatch), do: "✗ mismatch"
  defp status_label(:setup_error), do: "⚠ setup_error"
  defp status_label(:engine_error), do: "⚠ engine_error"
end
