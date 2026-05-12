defmodule AtomicFi.RuleEngine do
  @moduledoc """
  Behaviour for a pluggable rules/limits engine.

  ZenRule (`AtomicFi.ZenRule.HttpClient`) is the default implementation, selected
  via `config :atomic_fi, :rule_engine`. The engine is consulted synchronously
  during onboarding (AccountHolder / Counterparty / PaymentAccount create) and at
  transaction time — there is no Oban indirection.

  Given a domain entity (a transaction, …), `get_limits/1` returns the velocity
  limits to apply, **keyed by `ledger_account_id`**, as lists of
  `t:AtomicFi.LedgerAccountContext.VelocityLimit.t/0`. A ledger account already
  encodes the entity and the regulatory regime, so the caller resolves which
  ledger accounts are in play (the debtor/creditor leaf accounts and their
  ancestors), includes their ids in the payload, and threads the returned limits
  into `LedgerEntry.limits_at_entry` — the `ledger_entry_propagate_to_balances`
  trigger then fans them out to `ledger_account_balances.last_*_limit` up the
  ancestor chain, where the CHECK constraints enforce them.
  """

  alias AtomicFi.LedgerAccountContext.VelocityLimit

  @typedoc "Velocity limits to apply, keyed by ledger_account_id."
  @type limits :: %{optional(Ecto.UUID.t()) => [VelocityLimit.t()]}

  @callback get_limits(entity :: struct()) :: {:ok, limits()} | {:error, term()}

  @doc "The configured rule engine implementation module."
  @spec impl() :: module()
  def impl, do: Application.fetch_env!(:atomic_fi, :rule_engine)
end
