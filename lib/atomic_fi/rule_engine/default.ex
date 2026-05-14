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
    3. Decode each result into `%{ledger_account_id => Control.t()}`.
    4. Merge per-LA controls across rules — for overlapping LA ids the
       tighter (smaller) cap per slot wins.
    5. Empty merged map → `{:ok, :no_limits}`.
  """

  @behaviour AtomicFi.RuleEngine.Behaviour

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
          {:ok, %{optional(Ecto.UUID.t()) => Control.t()}}
          | {:ok, :no_limits}
          | {:error, term()}
  def_with_rls_and_logging get_controls(session, rule_type, entity),
    log_fields: [:rule_type] do
    with {:ok, names} <- RulesContext.list_rules(session, rule_type),
         {:ok, merged} <- evaluate_and_merge(rule_type, entity, names) do
      if map_size(merged) == 0, do: {:ok, :no_limits}, else: {:ok, merged}
    end
  end

  defp evaluate_and_merge(rule_type, entity, names) do
    project = RulesContext.project_name(rule_type)
    context = Payload.from_entity(entity)
    base_url = base_url()

    Enum.reduce_while(names, {:ok, %{}}, fn name, {:ok, acc} ->
      case evaluate_one(base_url, project, name, context) do
        {:ok, controls} -> {:cont, {:ok, merge_controls(acc, controls)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp evaluate_one(base_url, project, decision, context) do
    with {:ok, result} <- Client.evaluate(base_url, project, decision, context) do
      decode_controls(result)
    end
  end

  defp merge_controls(acc, controls) do
    Map.merge(acc, controls, fn _la_id, %Control{} = a, %Control{} = b ->
      Control.tighter(a, b)
    end)
  end

  defp base_url do
    :atomic_fi
    |> Application.fetch_env!(RuleEngine)
    |> Keyword.fetch!(:base_url)
  end

  defp decode_controls(%{"ledger_accounts" => by_id}) when is_map(by_id) do
    Enum.reduce_while(by_id, {:ok, %{}}, fn {la_id, attrs}, {:ok, acc} ->
      case decode_control(attrs) do
        {:ok, control} -> {:cont, {:ok, Map.put(acc, la_id, control)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp decode_controls(_other), do: {:ok, %{}}

  defp decode_control(%{} = attrs) do
    attrs
    |> Control.changeset()
    |> Changeset.apply_action(:cast)
  end
end
