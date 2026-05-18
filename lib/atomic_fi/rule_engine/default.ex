defmodule AtomicFi.RuleEngine.Default do
  @moduledoc """
  Default `AtomicFi.RuleEngine` impl — evaluates every rule under
  `rule_type` against the entity by POSTing to the GoRules Agent
  (ZenRule). Returns the raw per-rule outputs as a list; folding into
  one effective control map is `AtomicFi.RuleEngine.apply_rules/3`'s
  job, not this module's.

  Per-rule flow:

    1. List every JDM file under the rule_type's folder via
       `AtomicFi.RulesContext.list_rules/2` (ZenRule auto-loads the
       same directory).
    2. For each rule, POST to
       `<base_url>/api/projects/<project>/evaluate/<rule_name>` with
       the entity's payload (`AtomicFi.RuleEngine.Payload.from_entity/2`).
    3. Decode each response into
       `%{controls: %{la_id => Control}, next_screening_at: dt | nil}`.

  Rules whose output has no `ledger_accounts` map decode to empty
  controls + a logged warning (catches rules drifting from the
  expected output shape).
  """

  @behaviour AtomicFi.RuleEngine

  require Logger
  use AtomicFi.LoggerMacro

  alias AtomicFi.RuleEngine
  alias AtomicFi.RuleEngine.Control
  alias AtomicFi.RuleEngine.Payload
  alias AtomicFi.RulesContext
  alias AtomicFi.SessionContext.Session
  alias AtomicFi.ZenRule.Client
  alias Ecto.Changeset

  @impl AtomicFi.RuleEngine
  @spec get_controls(Session.t(), RuleEngine.rule_type(), struct()) ::
          {:ok, [RuleEngine.rule_result()]} | {:error, term()}
  def_with_rls_and_logging get_controls(session, rule_type, entity), log_fields: [:rule_type] do
    Logger.info(
      "[rule_engine] get_controls rule_type=#{inspect(rule_type)} entity=#{inspect(entity.__struct__)}"
    )

    with {:ok, names} <- RulesContext.list_rules(session, rule_type),
         _ = Logger.info("[rule_engine] rules listed: #{inspect(names)}") do
      base_url = base_url()
      project = RulesContext.project_name(rule_type)
      context = Payload.from_entity(session, entity)

      Enum.reduce_while(names, {:ok, []}, fn name, {:ok, acc} ->
        case evaluate_one(base_url, project, name, context) do
          {:ok, rule_result} -> {:cont, {:ok, [rule_result | acc]}}
          {:error, _} = err -> {:halt, err}
        end
      end)
      |> case do
        {:ok, results} -> {:ok, Enum.reverse(results)}
        err -> err
      end
    end
  end

  defp evaluate_one(base_url, project, decision, context) do
    Logger.info("[rule_engine] POST #{base_url} project=#{project} decision=#{decision}")
    t0 = System.monotonic_time(:millisecond)

    case Client.evaluate(base_url, project, decision, context) do
      {:ok, result} ->
        Logger.info(
          "[rule_engine] evaluate #{decision} OK in #{System.monotonic_time(:millisecond) - t0}ms"
        )

        decode_rule_result(result)

      {:error, reason} = err ->
        Logger.error(
          "[rule_engine] evaluate #{decision} ERROR in #{System.monotonic_time(:millisecond) - t0}ms reason=#{inspect(reason)}"
        )

        err
    end
  end

  defp base_url do
    :atomic_fi
    |> Application.fetch_env!(RuleEngine)
    |> Keyword.fetch!(:base_url)
  end

  defp decode_rule_result(%{"ledger_accounts" => by_id} = result) when is_map(by_id) do
    with {:ok, controls} <- decode_controls_map(by_id),
         {:ok, next} <- decode_next_screening_at(Map.get(result, "next_screening_at")) do
      {:ok, %{controls: controls, next_screening_at: next}}
    end
  end

  # Any result without a top-level "ledger_accounts" map is treated as
  # "engine produced no LA-shaped output". Right for rules that write to
  # transaction.* keys; also catches drift — a rule emitting the wrong
  # shape silently produces empty controls. Log a warning so the drift
  # is visible in test/dev runs.
  defp decode_rule_result(other) do
    Logger.warning(
      "rule_engine: rule output has no ledger_accounts map — result=#{inspect(other, limit: :infinity, printable_limit: 4096)}"
    )

    {:ok, %{controls: %{}, next_screening_at: nil}}
  end

  defp decode_controls_map(by_id) do
    Enum.reduce_while(by_id, {:ok, %{}}, fn {la_id, attrs}, {:ok, acc} ->
      case decode_control(attrs) do
        {:ok, control} -> {:cont, {:ok, Map.put(acc, la_id, control)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp decode_control(%{} = attrs) do
    attrs
    |> Control.changeset()
    |> Changeset.apply_action(:cast)
  end

  defp decode_next_screening_at(nil), do: {:ok, nil}
  # coveralls-ignore-next-line — JSON decode never yields %DateTime{} structs
  defp decode_next_screening_at(%DateTime{} = dt), do: {:ok, dt}

  defp decode_next_screening_at(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, reason} -> {:error, {:invalid_next_screening_at, reason}}
    end
  end

  # coveralls-ignore-next-line — JSON decode never yields non-string/non-nil here
  defp decode_next_screening_at(other), do: {:error, {:invalid_next_screening_at, other}}
end
