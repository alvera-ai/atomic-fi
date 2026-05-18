defmodule AtomicFi.RuleEngine do
  @moduledoc """
  Rule engine — public face + cross-rule fold.

  Callers (`AtomicFi.TransactionContext`, `OnboardingContext`, …) invoke
  `apply_rules/3` directly:

      RuleEngine.apply_rules(session, :transaction_screening, %Transaction{})
      RuleEngine.apply_rules(session, :onboarding, %AccountHolder{})

  ## Two-layer split

  ```
                              ┌────────────────────────────────────┐
   callers ──→ apply_rules ──→│ @rule_engine.get_controls(...)     │
                ↓             │   → [r1, r2, r3, ...]  per-rule    │
                ↓             └────────────────────────────────────┘
                │
                ▼
        fold across rules
        (effective_control/2 per LA;
         earliest non-nil next_screening_at)
                │
                ▼
        {:ok, %{controls: %{la_id => Control}, next_screening_at: dt}}
      | {:ok, :no_limits}
  ```

  The Behaviour callback `get_controls/3` is the impl's contract: list
  every rule under `rule_type`, evaluate each, return the raw list. No
  merging happens in the impl. `apply_rules/3` is the public surface
  that folds the list into a single effective control map; that fold
  is the same for every impl so it lives here once.

  ## Pluggable impl

  Compile-time resolved via the `:rule_engine` config slice. Default is
  `AtomicFi.RuleEngine.Default` (HTTP to ZenRule). Tests swap in
  `AtomicFi.RuleEngineMock`, which `stub_with`s the Default so unstubbed
  tests fall through to the real engine.

  ## Effective control (industry term: *effective limit*)

  Per LA, across all rules that fired:

    * cap = min of all non-nil caps (strictest cap wins; nil = ∞)
    * is_blocked = OR across rules
    * block_reason = `; `-joined audit of every rule that BLOCKED
                     (a non-blocking tag never bleeds into the
                     block reason)
    * reason = `; `-joined audit of every rule that fired

  Matches how Stripe / Adyen / card-network docs describe limit
  stacking after issuer, regulatory, and velocity overlays combine.

  ## Config

      config :atomic_fi, AtomicFi.RuleEngine, base_url: "http://localhost:8090"
  """

  require Logger

  alias AtomicFi.RuleEngine.Control
  alias AtomicFi.RuleEngine.Default
  alias AtomicFi.SessionContext.Session

  @typedoc "Rule bucket — maps 1:1 to a ZenRule project (kebab-case folder slug)."
  @type rule_type :: :onboarding | :transaction_screening

  @typedoc "Controls keyed by ledger_account_id."
  @type controls :: %{optional(Ecto.UUID.t()) => Control.t()}

  @typedoc """
  Per-rule output envelope returned by `get_controls/3` impls (one
  element per rule that fired).

    * `:controls` — per-LA Controls this rule emitted.
    * `:next_screening_at` — re-screening hint from this rule, or `nil`.
  """
  @type rule_result :: %{
          controls: controls(),
          next_screening_at: DateTime.t() | nil
        }

  @typedoc """
  Folded result returned by `apply_rules/3`. `next_screening_at` is the
  earliest non-nil hint across all rules.
  """
  @type folded :: %{
          controls: controls(),
          next_screening_at: DateTime.t() | nil
        }

  @doc """
  List every rule under `rule_type`, evaluate each against `entity`,
  return the raw per-rule outputs as a list. NO merging — that's
  `apply_rules/3`'s job.

  Implemented by `AtomicFi.RuleEngine.Default` (HTTP to ZenRule).
  Mox seam for tests.
  """
  @callback get_controls(
              session :: Session.t(),
              rule_type :: rule_type(),
              entity :: struct()
            ) :: {:ok, [rule_result()]} | {:error, term()}

  @rule_engine Application.compile_env(:atomic_fi, :rule_engine, Default)

  @doc """
  Public API: ask the impl for the raw per-rule outputs, then fold them
  into the effective control map. Empty merged controls + nil hint →
  `{:ok, :no_limits}`; otherwise `{:ok, folded}`.
  """
  @spec apply_rules(Session.t(), rule_type(), struct()) ::
          {:ok, folded()} | {:ok, :no_limits} | {:error, term()}
  def apply_rules(session, rule_type, entity) do
    Logger.info(
      "[rule_engine] apply_rules rule_type=#{inspect(rule_type)} entity=#{inspect(entity.__struct__)}"
    )

    with {:ok, results} <- @rule_engine.get_controls(session, rule_type, entity) do
      %{controls: controls, next_screening_at: next} = merged = fold(results)
      Logger.info("[rule_engine] fold done controls=#{map_size(controls)} next=#{inspect(next)}")

      if map_size(controls) == 0 and is_nil(next),
        do: {:ok, :no_limits},
        else: {:ok, merged}
    end
  end

  @doc """
  Fold a list of per-rule outputs into one merged envelope.
  """
  @spec fold([rule_result()]) :: folded()
  def fold(results) when is_list(results) do
    Enum.reduce(results, %{controls: %{}, next_screening_at: nil}, &fold_one(&2, &1))
  end

  defp fold_one(a, b) do
    %{
      controls:
        Map.merge(a.controls, b.controls, fn _la_id, %Control{} = c1, %Control{} = c2 ->
          effective_control(c1, c2)
        end),
      next_screening_at: earliest(a.next_screening_at, b.next_screening_at)
    }
  end

  defp earliest(nil, b), do: b
  defp earliest(a, nil), do: a
  defp earliest(a, b), do: if(DateTime.compare(a, b) == :lt, do: a, else: b)

  @doc """
  Effective control on one LA when two rules both emitted — see module
  doc for semantics. Fan-in across N rules is via `fold/1`.
  """
  @spec effective_control(Control.t(), Control.t()) :: Control.t()
  def effective_control(%Control{} = a, %Control{} = b) do
    %Control{
      daily_debit_cap: min_cap(a.daily_debit_cap, b.daily_debit_cap),
      daily_credit_cap: min_cap(a.daily_credit_cap, b.daily_credit_cap),
      weekly_debit_cap: min_cap(a.weekly_debit_cap, b.weekly_debit_cap),
      weekly_credit_cap: min_cap(a.weekly_credit_cap, b.weekly_credit_cap),
      monthly_debit_cap: min_cap(a.monthly_debit_cap, b.monthly_debit_cap),
      monthly_credit_cap: min_cap(a.monthly_credit_cap, b.monthly_credit_cap),
      yearly_debit_cap: min_cap(a.yearly_debit_cap, b.yearly_debit_cap),
      yearly_credit_cap: min_cap(a.yearly_credit_cap, b.yearly_credit_cap),
      is_blocked: a.is_blocked or b.is_blocked,
      block_reason: merge_block_reasons(a, b),
      reason: merge_strings(a.reason, b.reason)
    }
  end

  defp min_cap(nil, b), do: b
  defp min_cap(a, nil), do: a
  defp min_cap(a, b), do: min(a, b)

  defp merge_strings(nil, b), do: b
  defp merge_strings(a, nil), do: a
  defp merge_strings(a, a), do: a
  defp merge_strings(a, b), do: "#{a}; #{b}"

  defp merge_block_reasons(%Control{is_blocked: false}, %Control{is_blocked: false}), do: nil

  defp merge_block_reasons(%Control{is_blocked: true} = a, %Control{is_blocked: false}),
    do: a.block_reason

  defp merge_block_reasons(%Control{is_blocked: false}, %Control{is_blocked: true} = b),
    do: b.block_reason

  defp merge_block_reasons(%Control{is_blocked: true} = a, %Control{is_blocked: true} = b),
    do: merge_strings(a.block_reason, b.block_reason)
end
