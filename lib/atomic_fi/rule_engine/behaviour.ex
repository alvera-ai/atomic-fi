defmodule AtomicFi.RuleEngine.Behaviour do
  @moduledoc """
  Domain-level contract for the velocity/limits rule engine.

  Implementations take a fully-preloaded domain entity (today: `%Transaction{}`
  with its debtor/creditor PA + CP + AH chain) and return velocity limits
  keyed by `ledger_account_id`. Implementations are pure with respect to
  persistence — callers (`AtomicFi.TransactionContext`,
  `AtomicFi.AccountHolderContext`, `AtomicFi.CounterpartyContext`) write the
  resulting ledger entries.

  Mirrors `AtomicFi.ScreeningEngine.Behaviour` — same
  separation between transport (`AtomicFi.ZenRule.Client`) and domain
  (`AtomicFi.RuleEngine`).
  """

  alias AtomicFi.RuleEngine.Control
  alias AtomicFi.SessionContext.Session

  @typedoc "Rule bucket — maps 1:1 to a ZenRule project (kebab-case folder slug)."
  @type rule_type :: :onboarding | :transaction_screening

  @typedoc "Controls to apply, keyed by ledger_account_id."
  @type controls :: %{optional(Ecto.UUID.t()) => Control.t()}

  @callback get_controls(Session.t(), rule_type(), entity :: struct()) ::
              {:ok, controls()} | {:ok, :no_limits} | {:error, term()}
end
