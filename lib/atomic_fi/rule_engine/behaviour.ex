defmodule AtomicFi.RuleEngine.Behaviour do
  @moduledoc """
  Domain-level contract for the velocity/limits rule engine.

  Implementations take a fully-preloaded domain entity (today: `%Transaction{}`
  with its debtor/creditor PA + CP + AH chain) and return velocity limits
  keyed by `ledger_account_id`. Implementations are pure with respect to
  persistence — callers (`AtomicFi.TransactionContext`) write the resulting
  ledger entries.

  Mirrors `AtomicFi.DecisionContext.ScreeningEngine.Behaviour` — the screening
  engine's behaviour module — same separation between transport
  (`AtomicFi.ZenRule.Client`) and domain (`AtomicFi.RuleEngine.ZenRule`).
  """

  alias AtomicFi.LedgerAccountContext.VelocityLimit

  @typedoc "Velocity limits to apply, keyed by ledger_account_id."
  @type limits :: %{optional(Ecto.UUID.t()) => [VelocityLimit.t()]}

  @callback get_limits(entity :: struct()) :: {:ok, limits()} | {:error, term()}
end
