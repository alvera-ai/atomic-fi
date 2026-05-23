defmodule AtomicFi.ZenRule.Client do
  @moduledoc """
  Pure transport client for the GoRules Agent (ZenRule).

  Mirrors `AtomicFi.Watchman.Client` — a thin Req-based HTTP wrapper that
  returns the decoded JSON `"result"` map (or an error envelope) and
  nothing more. **No domain shaping, no behaviour, no config lookup.**
  Domain mapping (raw JDM result → `%ControlLimit{}` keyed by
  `ledger_account_id`) lives one level up in `AtomicFi.RuleEngine`,
  which also owns its config slice.

      POST <base_url>/api/projects/<project>/evaluate/<decision>
        {"context": <entity tree>}
      → 200 {"result": <decision-shaped map>, "performance": "...", ...}

  `project` corresponds to a top-level subdir under the ZenRule rules
  root (one per `rule_type` in `AtomicFi.RulesContext.project_name/1`).

  Defensive transport / decode arms are `# coveralls-ignore`'d — treated
  like a database driver per CLAUDE.md §"External Service Boundaries".
  """

  @doc """
  Evaluates a JDM decision file against the given context, returning the
  raw `"result"` map.
  """
  @spec evaluate(String.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def evaluate(base_url, project, decision, context)
      when is_binary(base_url) and is_binary(project) and is_binary(decision) and
             is_map(context) do
    url = "/api/projects/#{project}/evaluate/#{decision}"

    case Req.post(req(base_url), url: url, json: %{context: context}) do
      {:ok, %{status: 200, body: %{"result" => result}}} when is_map(result) ->
        {:ok, result}

      # coveralls-ignore-start: defensive transport — treated like a DB driver
      {:ok, %{status: 200, body: body}} ->
        {:error, {:unexpected_body, body}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
        # coveralls-ignore-stop
    end
  end

  defp req(base_url) do
    # Route through the dedicated `AtomicFi.ZenRule.Finch` pool —
    # sized in config/{config,test,runtime}.exs so RuleEngine's
    # per-rule POST fan-out doesn't exhaust the shared Req/Finch pool
    # under `mix test` concurrency (max_cases = scheduler count).
    Req.new(
      base_url: base_url,
      headers: [{"accept", "application/json"}],
      finch: AtomicFi.ZenRule.Finch
    )
  end
end
