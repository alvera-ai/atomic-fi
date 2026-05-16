defmodule Mix.Tasks.Corpus.Validate do
  @shortdoc "Replays committed fixture payloads against the live ZenRule agent and prints a markdown drift report"

  @moduledoc """
  Walks fixture directories under `test/support/upstream/**` matching the
  given glob, POSTs each `payload.json` to the running ZenRule agent, and
  emits a markdown report on stdout (or `--out <path>`).

  Each fixture is reported in detail (request, response, expectation diff),
  followed by a summary block at the end.

  Fixture directory shape:

      test/support/upstream/<src>/fixtures/<scenario>/
        payload.json     ← the rule-engine `context` (POSTed verbatim)
        expected.json    ← OPTIONAL — full prior rule-engine `result` body.
                            When absent, this run is reported as `new`
                            (first-time capture) instead of `mismatch`.
        _label.json      ← { source, rule_type, rule_decision, regime,
                             cite, verdict }

  Usage:

      $ mix corpus.validate                                      # all fixtures
      $ mix corpus.validate "de_minimis/**"                      # one rule
      $ mix corpus.validate "stableaml/fixtures/sdn-*"            # path glob
      $ mix corpus.validate "**" --out tmp/corpus/report.md       # write to file

  Requires the ZenRule agent reachable at the URL configured in
  `:atomic_fi, AtomicFi.RuleEngine, :base_url`. `make run-backing-services`
  brings it up.
  """

  use Mix.Task

  alias AtomicFi.RuleEngine
  alias AtomicFi.ZenRule.Client

  @fixtures_root "test/support/upstream"

  @impl true
  def run(args) do
    {opts, positional, _} = OptionParser.parse(args, strict: [out: :string])
    glob = List.first(positional) || "**"

    Mix.Task.run("app.start")

    base_url =
      :atomic_fi |> Application.fetch_env!(RuleEngine) |> Keyword.fetch!(:base_url)

    rows =
      @fixtures_root
      |> find_fixture_dirs(glob)
      |> Enum.map(&validate_one(&1, base_url))

    report = render_markdown(rows, base_url)

    case opts[:out] do
      nil ->
        IO.write(report)

      path ->
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, report)
        Mix.shell().info("✓ Wrote validation report to #{path}")
    end

    if Enum.any?(rows, &(&1.status in [:mismatch, :engine_error])) do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end

  defp find_fixture_dirs(root, glob) do
    pattern = Path.join([root, glob, "_label.json"])

    pattern
    |> Path.wildcard()
    |> Enum.map(&Path.dirname/1)
    |> Enum.sort()
  end

  defp validate_one(dir, base_url) do
    label = read_json!(dir, "_label.json")
    payload = read_json!(dir, "payload.json")
    expected = read_optional_json(dir, "expected.json")

    rule_type = Map.fetch!(label, "rule_type")
    decision = Map.fetch!(label, "rule_decision")
    project = rule_type_project!(rule_type)

    case Client.evaluate(base_url, project, decision, payload) do
      {:ok, actual} ->
        status =
          cond do
            is_nil(expected) -> :new
            actual == expected -> :match
            true -> :mismatch
          end

        %{
          dir: dir,
          label: label,
          payload: payload,
          expected: expected,
          actual: actual,
          status: status
        }

      {:error, reason} ->
        %{
          dir: dir,
          label: label,
          payload: payload,
          expected: expected,
          actual: nil,
          status: :engine_error,
          error: reason
        }
    end
  end

  defp read_json!(dir, file) do
    dir |> Path.join(file) |> File.read!() |> Jason.decode!()
  end

  defp read_optional_json(dir, file) do
    path = Path.join(dir, file)
    if File.exists?(path), do: path |> File.read!() |> Jason.decode!(), else: nil
  end

  defp rule_type_project!(rule_type) do
    rt = String.to_existing_atom(rule_type)
    AtomicFi.RulesContext.project_name(rt)
  end

  # ───────────────────────────── rendering ─────────────────────────────

  defp render_markdown(rows, base_url) do
    header = """
    # corpus.validate report

    - zenrule: #{base_url}
    - ts: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    - fixtures: #{length(rows)}

    """

    details =
      if rows == [] do
        "_No fixtures matched the glob._\n\n"
      else
        Enum.map_join(rows, "\n", &render_fixture/1)
      end

    summary = render_summary(rows)

    header <> details <> "\n" <> summary
  end

  defp render_fixture(%{dir: dir, status: status} = row) do
    rel = Path.relative_to(dir, @fixtures_root)
    label = row.label

    """
    ## #{rel}

    - status:   **#{status_label(status)}**
    - source:   #{Map.get(label, "source", "?")}
    - rule:     #{Map.get(label, "rule_type", "?")} / #{Map.get(label, "rule_decision", "?")}
    - cite:     #{Map.get(label, "cite", "—")}
    - verdict:  #{Map.get(label, "verdict", "?")}

    #{render_bodies(row)}
    """
  end

  defp render_bodies(%{status: :engine_error, error: reason, payload: payload}) do
    """
    ```text
    engine error: #{inspect(reason)}
    ```

    <details><summary>payload</summary>

    ```json
    #{Jason.encode!(payload, pretty: true)}
    ```
    </details>
    """
  end

  defp render_bodies(%{status: :new, payload: payload, actual: actual}) do
    """
    <details><summary>payload</summary>

    ```json
    #{Jason.encode!(payload, pretty: true)}
    ```
    </details>

    <details open><summary>actual response (no expected.json on disk yet)</summary>

    ```json
    #{Jason.encode!(actual, pretty: true)}
    ```
    </details>
    """
  end

  defp render_bodies(%{status: :match, payload: payload, actual: actual}) do
    """
    <details><summary>payload</summary>

    ```json
    #{Jason.encode!(payload, pretty: true)}
    ```
    </details>

    <details><summary>response (matches expected)</summary>

    ```json
    #{Jason.encode!(actual, pretty: true)}
    ```
    </details>
    """
  end

  defp render_bodies(%{status: :mismatch, payload: payload, expected: expected, actual: actual}) do
    """
    <details><summary>payload</summary>

    ```json
    #{Jason.encode!(payload, pretty: true)}
    ```
    </details>

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
    | new (no expected.json) | #{Map.get(counts, :new, 0)} |
    | mismatch | #{Map.get(counts, :mismatch, 0)} |
    | engine_error | #{Map.get(counts, :engine_error, 0)} |
    | **total** | **#{length(rows)}** |
    """
  end

  defp status_label(:match), do: "✓ match"
  defp status_label(:new), do: "🆕 new (no expected.json)"
  defp status_label(:mismatch), do: "✗ mismatch"
  defp status_label(:engine_error), do: "⚠ engine_error"
end
