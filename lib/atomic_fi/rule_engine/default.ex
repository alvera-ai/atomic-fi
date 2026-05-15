defmodule AtomicFi.RuleEngine.Default do
  @moduledoc """
  Default rule-engine implementation — orchestrates JDM evaluation
  against the GoRules Agent (ZenRule) over HTTP.

  Wired in via `AtomicFi.RuleEngine` (the public dispatcher).

  ## Flow

  Given a `rule_type` (`:onboarding | :transaction_screening`) and a
  fully-preloaded domain entity:

    1. List every JDM file under the rule_type's folder via
       `AtomicFi.RulesContext.list_rules/2` (ZenRule mounts and
       auto-loads the same directory).
    2. For each rule, call
       `AtomicFi.ZenRule.Client.evaluate(base_url, project, decision, ctx)`
       where `project = RulesContext.project_name(rule_type)`.
    3. Decode each rule result into
       `%{controls: %{la_id => Control}, next_screening_at: DateTime | nil}`.
    4. Merge across rules — per-LA controls combine with `Control.tighter/2`
       (smaller cap wins per slot); `next_screening_at` takes the earliest
       non-nil value.
    5. Empty merged controls map → `{:ok, :no_limits}`.
  """

  @behaviour AtomicFi.RuleEngine.Behaviour

  require Logger
  use AtomicFi.LoggerMacro

  alias AtomicFi.RuleEngine
  alias AtomicFi.RuleEngine.Control
  alias AtomicFi.RuleEngine.Payload
  alias AtomicFi.RulesContext
  alias AtomicFi.SessionContext.Session
  alias AtomicFi.ZenRule.Client
  alias Ecto.Changeset

  @impl AtomicFi.RuleEngine.Behaviour
  @spec get_controls(Session.t(), RulesContext.rule_type(), struct()) ::
          {:ok, AtomicFi.RuleEngine.Behaviour.result()}
          | {:ok, :no_limits}
          | {:error, term()}
  def_with_rls_and_logging get_controls(session, rule_type, entity),
    log_fields: [:rule_type] do
    with {:ok, names} <- RulesContext.list_rules(session, rule_type),
         {:ok, %{controls: controls} = merged} <- evaluate_and_merge(rule_type, entity, names) do
      if map_size(controls) == 0, do: {:ok, :no_limits}, else: {:ok, merged}
    end
  end

  defp evaluate_and_merge(rule_type, entity, names) do
    project = RulesContext.project_name(rule_type)
    context = Payload.from_entity(entity)
    base_url = base_url()
    empty = %{controls: %{}, next_screening_at: nil}

    Enum.reduce_while(names, {:ok, empty}, fn name, {:ok, acc} ->
      case evaluate_one(base_url, project, name, context) do
        {:ok, rule_result} -> {:cont, {:ok, merge_results(acc, rule_result)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp evaluate_one(base_url, project, decision, context) do
    with {:ok, result} <- Client.evaluate(base_url, project, decision, context) do
      decode_rule_result(result)
    end
  end

  defp merge_results(a, b) do
    %{
      controls:
        Map.merge(a.controls, b.controls, fn _la_id, %Control{} = c1, %Control{} = c2 ->
          Control.tighter(c1, c2)
        end),
      next_screening_at: earliest(a.next_screening_at, b.next_screening_at)
    }
  end

  defp earliest(nil, b), do: b
  defp earliest(a, nil), do: a
  defp earliest(a, b), do: if(DateTime.compare(a, b) == :lt, do: a, else: b)

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

  # Any result that doesn't have a top-level "ledger_accounts" map is treated as
  # "engine produced no LA-shaped output". This is the right behaviour for rules
  # like de_minimis.json that write to transaction.* keys (no LA controls to
  # apply), but it also catches drift — a rule that mistakenly emits the wrong
  # shape will silently produce :no_limits. Log a warning so the drift is
  # visible in test/dev runs.
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
