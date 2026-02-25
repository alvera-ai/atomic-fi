defmodule PaymentCompliancePlatform.LedgerAccountBalanceContext do
  @moduledoc """
  LedgerAccountBalance context — read-only access to daily balance snapshots.

  Balance rows are created and updated entirely by the
  `ledger_entry_propagate_to_balances` PostgreSQL trigger — never by application
  code directly. This context provides list and show operations only.

  Each row carries day/week/month/year cumulative totals (in minor currency units)
  and the last known velocity limits propagated from the risk engine via the
  triggering ledger_entry's *_limit_at_entry snapshot columns.

  Velocity limit enforcement is DB-driven:
      CHECK (last_daily_debit_limit IS NULL OR daily_debit <= last_daily_debit_limit)
  """

  import Ecto.Query, warn: false
  use PaymentCompliancePlatform.LoggerMacro

  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.LedgerAccountContext.LedgerAccountBalance
  alias PaymentCompliancePlatform.SessionContext.Session

  @doc """
  Returns the list of ledger_account_balances with pagination and filtering.

  ## Examples

      iex> list_ledger_account_balances(session, %{page: 1, page_size: 20})
      {:ok, {[%LedgerAccountBalance{}, ...], %Flop.Meta{}}}

  """
  @spec list_ledger_account_balances(Session.t(), map()) ::
          {:ok, {list(LedgerAccountBalance.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_ledger_account_balances(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    LedgerAccountBalance
    |> Flop.validate_and_run(flop_params,
      for: LedgerAccountBalance,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single ledger_account_balance.

  Raises `Ecto.NoResultsError` if the LedgerAccountBalance does not exist.

  ## Examples

      iex> get_ledger_account_balance!(session, "123")
      %LedgerAccountBalance{}

      iex> get_ledger_account_balance!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_ledger_account_balance!(Session.t(), Ecto.UUID.t()) :: LedgerAccountBalance.t()
  def_with_rls_and_logging get_ledger_account_balance!(session, id), log_fields: [:id] do
    Repo.get!(LedgerAccountBalance, id, session: session)
  end
end
