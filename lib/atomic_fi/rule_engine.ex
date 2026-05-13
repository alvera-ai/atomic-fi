defmodule AtomicFi.RuleEngine do
  @moduledoc """
  Dispatch wrapper for the configured rule engine implementation.

  The default impl is `AtomicFi.RuleEngine.ZenRule` (backed by the GoRules
  Agent over HTTP via `AtomicFi.ZenRule.Client`), selected via
  `config :atomic_fi, :rule_engine`. The engine is consulted synchronously
  during onboarding (AccountHolder / Counterparty / PaymentAccount create)
  and at transaction time — no Oban indirection.

  Given a domain entity, `get_limits/1` returns the velocity limits to
  apply, **keyed by `ledger_account_id`**, as lists of
  `t:AtomicFi.LedgerAccountContext.VelocityLimit.t/0`. A ledger account
  already encodes the entity and the regulatory regime, so the caller
  resolves which ledger accounts are in play (the debtor/creditor leaf
  accounts and their ancestors), includes their ids in the payload, and
  threads the returned limits into `LedgerEntry.limits_at_entry` — the
  `ledger_entry_propagate_to_balances` trigger then fans them out to
  `ledger_account_balances.last_*_limit` up the ancestor chain, where the
  CHECK constraints enforce them.

  The contract lives in `AtomicFi.RuleEngine.Behaviour`; this module only
  hides the impl lookup and translates an empty-limits success into the
  `:no_limits` sentinel callers pattern-match on.
  """

  alias AtomicFi.RuleEngine.Behaviour

  @doc """
  Asks the configured rule engine for velocity limits applicable to `entity`.

  Returns:
    * `{:ok, limits}`     — non-empty per-ledger-account limits to enforce
    * `{:ok, :no_limits}` — engine declined to score (e.g. no rules applicable)
    * `{:error, reason}`  — transport / decode error

  Callers should pattern-match `:no_limits` to skip ledger writes entirely.
  """
  @spec get_limits(struct()) :: {:ok, Behaviour.limits()} | {:ok, :no_limits} | {:error, term()}
  def get_limits(entity) when is_struct(entity) do
    case impl().get_limits(entity) do
      {:ok, limits} when is_map(limits) and map_size(limits) == 0 -> {:ok, :no_limits}
      {:ok, limits} when is_map(limits) -> {:ok, limits}
      {:error, _} = err -> err
    end
  end

  defp impl, do: Application.fetch_env!(:atomic_fi, :rule_engine)
end
