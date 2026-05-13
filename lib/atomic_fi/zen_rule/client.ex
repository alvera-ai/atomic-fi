defmodule AtomicFi.ZenRule.Client do
  @moduledoc """
  Pure transport client for the GoRules Agent (ZenRule).

  Mirrors `AtomicFi.Watchman.Client` — a thin Req-based HTTP wrapper that
  returns the decoded JSON `"result"` map (or an error envelope) and
  nothing more. **No domain shaping, no behaviour, no config lookup.**
  Domain mapping (raw JDM result → `%VelocityLimit{}` keyed by
  `ledger_account_id`) lives one level up in `AtomicFi.RuleEngine.ZenRule`,
  which also owns its config slice.

      POST <base_url>/api/projects/atomic-fi/evaluate/<decision>
        {"context": <entity tree>}
      → 200 {"result": <decision-shaped map>, "performance": "...", ...}

  Defensive transport / decode arms are `# coveralls-ignore`'d — treated
  like a database driver per CLAUDE.md §"External Service Boundaries".
  """

  @project "atomic-fi"

  @doc """
  Evaluates a JDM decision file against the given context, returning the
  raw `"result"` map.
  """
  @spec evaluate(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def evaluate(base_url, decision, context)
      when is_binary(base_url) and is_binary(decision) and is_map(context) do
    url = "/api/projects/#{@project}/evaluate/#{decision}"

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
    Req.new(base_url: base_url, headers: [{"accept", "application/json"}])
  end
end
