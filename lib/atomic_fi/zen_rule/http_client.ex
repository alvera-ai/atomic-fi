defmodule AtomicFi.ZenRule.HttpClient do
  @moduledoc """
  `AtomicFi.RuleEngine` implementation backed by the GoRules Agent (ZenRule).

  Mirrors the Watchman client pattern: a thin Req-based HTTP client against the
  locally-run agent. POSTs the entity context (built by `AtomicFi.RuleEngine.Payload`)
  to the agent's evaluate endpoint and maps the JDM decision result into velocity
  limits keyed by `ledger_account_id`.

      POST <zen_rule_base_url>/api/projects/atomic-fi/evaluate/de_minimis.json
        {"context": <entity tree incl. the ledger_account ids in play>}
      → 200 {"result": {"ledger_accounts": {
                "<la_id>": [{"period":"weekly","direction":"debit","cap":50000,"rule":"..."}, …], …}}, …}

  ## Configuration

      config :atomic_fi, :zen_rule_base_url, System.get_env("ZEN_RULE_URL")

  Rules live as JSON Decision Model files under `priv/zenrule/` — bind-mounted
  into the agent, hot-reloaded on its poll interval. See `local-dependencies.yaml`
  and `external-deps/zenrule/`.
  """

  @behaviour AtomicFi.RuleEngine

  alias AtomicFi.Config
  alias AtomicFi.LedgerAccountContext.VelocityLimit
  alias AtomicFi.RuleEngine.Payload

  @project "atomic-fi"
  @decision "de_minimis.json"

  @impl AtomicFi.RuleEngine
  def get_limits(entity) when is_struct(entity) do
    url = "/api/projects/#{@project}/evaluate/#{@decision}"
    context = Payload.from_entity(entity)

    case Req.post(build_req(), url: url, json: %{context: context}) do
      {:ok, %{status: 200, body: %{"result" => result}}} when is_map(result) ->
        {:ok, decode_limits(result)}

      {:ok, %{status: 200, body: body}} ->
        {:error, {:unexpected_body, body}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_req do
    Req.new(
      base_url: Config.fetch!(:zen_rule_base_url),
      headers: [{"accept", "application/json"}]
    )
  end

  defp decode_limits(%{"ledger_accounts" => by_id}) when is_map(by_id) do
    Map.new(by_id, fn {la_id, lines} -> {la_id, decode_lines(lines)} end)
  end

  defp decode_limits(_other), do: %{}

  defp decode_lines(lines) when is_list(lines), do: Enum.map(lines, &decode_line/1)
  defp decode_lines(_), do: []

  defp decode_line(%{} = line) do
    %VelocityLimit{
      period: line["period"],
      direction: line["direction"],
      cap: line["cap"],
      rule: line["rule"]
    }
  end
end
