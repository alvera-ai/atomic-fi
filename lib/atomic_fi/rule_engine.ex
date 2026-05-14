defmodule AtomicFi.RuleEngine do
  @moduledoc """
  Rule engine — public face (dispatcher).

  Callers (`AtomicFi.TransactionContext`, `AccountHolderContext`,
  `CounterpartyContext`) invoke this module directly:

      RuleEngine.get_controls(session, :transaction_screening, %Transaction{} = txn)
      RuleEngine.get_controls(session, :onboarding, %AccountHolder{} = ah)

  The configured impl module (defaults to `AtomicFi.RuleEngine.Default`;
  tests swap in `AtomicFi.RuleEngineMock`) is resolved at compile time
  via the `:rule_engine` config slice. The swap is **invisible to
  callers** — this dispatcher delegates the Behaviour call straight
  through.

  ## Mock seam

  `DataCase / ConnCase` setup hook calls
  `Mox.stub_with(RuleEngineMock, RuleEngine.Default)` so the mock falls
  through to the real engine by default; per-test
  `Mox.expect(RuleEngineMock, :get_controls, fn _, _, _ -> … end)` overrides
  without setting up ZenRule state.

  ## Config

      config :atomic_fi, AtomicFi.RuleEngine, base_url: "http://localhost:8090"
  """

  @behaviour AtomicFi.RuleEngine.Behaviour

  alias AtomicFi.RuleEngine.Control
  alias AtomicFi.RuleEngine.Default
  alias AtomicFi.RulesContext
  alias AtomicFi.SessionContext.Session

  @rule_engine Application.compile_env(:atomic_fi, :rule_engine, Default)

  @impl true
  @spec get_controls(Session.t(), RulesContext.rule_type(), struct()) ::
          {:ok, %{optional(Ecto.UUID.t()) => Control.t()}}
          | {:ok, :no_limits}
          | {:error, term()}
  def get_controls(session, rule_type, entity),
    do: @rule_engine.get_controls(session, rule_type, entity)
end
