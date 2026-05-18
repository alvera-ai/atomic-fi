defmodule AtomicFi.RuleEngine.Default do
  @moduledoc """
  Default `AtomicFi.RuleEngine` impl — the JDM transport step.

  `AtomicFi.RuleEngine` (the common layer) owns payload assembly, rule
  discovery, fan-out, and folding. This module's sole responsibility is
  evaluating one `(project, decision, payload)` tuple against the
  GoRules Agent (ZenRule) over HTTP and decoding the response into one
  `rule_result`.

  Per-call flow:

    1. POST to `<base_url>/api/projects/<project>/evaluate/<decision>`
       with the prepared payload.
    2. Decode the JDM output into
       `%{controls: %{la_id => Control}, next_screening_at: dt | nil}`.

  Rules whose output has no `ledger_accounts` map decode to empty
  controls + a logged warning (catches rules drifting from the
  expected output shape).

  Swapping this impl (e.g. an in-process NIF) only requires
  implementing `evaluate/4` — every other concern (rule listing,
  parallel fan-out, payload assembly, fold) stays in
  `AtomicFi.RuleEngine`.
  """

  @behaviour AtomicFi.RuleEngine

  require Logger
  use AtomicFi.LoggerMacro

  alias AtomicFi.RuleEngine
  alias AtomicFi.RuleEngine.Control
  alias AtomicFi.SessionContext.Session
  alias AtomicFi.ZenRule.Client
  alias Ecto.Changeset

  @impl AtomicFi.RuleEngine
  @spec evaluate(Session.t(), String.t(), String.t(), RuleEngine.payload()) ::
          {:ok, RuleEngine.rule_result()} | {:error, term()}
  def_with_rls_and_logging evaluate(session, project, decision, payload),
    log_fields: [:project, :decision] do
    _ = session
    base_url = base_url()
    Logger.info("[rule_engine] POST #{base_url} project=#{project} decision=#{decision}")
    t0 = System.monotonic_time(:millisecond)

    case Client.evaluate(base_url, project, decision, payload) do
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
