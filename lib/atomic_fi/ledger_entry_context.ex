defmodule AtomicFi.LedgerEntryContext do
  @moduledoc """
  LedgerEntry context — manages individual debit/credit line items (ISO 20022 CdtDbtInd).

  All balance propagation is handled by the `ledger_entry_propagate_to_balances`
  PostgreSQL trigger, which fires AFTER INSERT or AFTER UPDATE OF status ON ledger_entries:

  - INSERT: increments ledger_accounts.balance (credit = +, debit = –) and upserts
    ledger_account_balances rows for the direct account and all ancestor accounts.
  - UPDATE status → voided: reverses all the above (negative delta).

  Velocity limit enforcement is DB-driven via CHECK constraints on ledger_account_balances.
  The orchestration layer supplies *_limit_at_entry snapshot columns on the entry row;
  the trigger copies them to last_*_limit on the balance row so CHECK constraints fire.

  This context does NOT perform manual Repo.update_all balance increments — the trigger
  handles all propagation.
  """

  import Ecto.Query, warn: false
  use AtomicFi.LoggerMacro

  alias AtomicFi.OpenApiSchema.LedgerEntryRequest
  alias AtomicFi.Repo
  alias AtomicFi.LedgerEntryContext.LedgerEntry
  alias AtomicFi.SessionContext.Session

  @doc """
  Returns the list of ledger_entries with pagination and filtering.

  ## Examples

      iex> list_ledger_entries(session, %{page: 1, page_size: 20})
      {:ok, {[%LedgerEntry{}, ...], %Flop.Meta{}}}

  """
  @spec list_ledger_entries(Session.t(), map()) ::
          {:ok, {list(LedgerEntry.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_ledger_entries(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    LedgerEntry
    |> Flop.validate_and_run(flop_params,
      for: LedgerEntry,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single ledger_entry.

  Raises `Ecto.NoResultsError` if the LedgerEntry does not exist.

  ## Examples

      iex> get_ledger_entry!(session, "123")
      %LedgerEntry{}

      iex> get_ledger_entry!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_ledger_entry!(Session.t(), Ecto.UUID.t()) :: LedgerEntry.t()
  def_with_rls_and_logging get_ledger_entry!(session, id), log_fields: [:id] do
    Repo.get!(LedgerEntry, id, session: session)
  end

  @doc """
  Creates a ledger_entry.

  The DB trigger `ledger_entry_propagate_to_balances` fires after the INSERT and:
  - Updates ledger_accounts.balance (credit = +, debit = –)
  - Upserts ledger_account_balances rows for the direct account and all ancestors
  - Copies *_limit_at_entry to last_*_limit on balance rows (for CHECK constraint enforcement)

  Velocity limit snapshots (*_limit_at_entry) must be set on the request by the
  orchestration layer from the risk engine before calling this function. NULL = unconstrained.

  ## Examples

      iex> create_ledger_entry(session, %{entry_type: :credit, amount: 5000, ...})
      {:ok, %LedgerEntry{}}

  """
  @spec create_ledger_entry(Session.t(), LedgerEntryRequest.t()) ::
          {:ok, LedgerEntry.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_ledger_entry(session, %LedgerEntryRequest{} = request),
    log_fields: [] do
    %LedgerEntry{}
    |> LedgerEntry.changeset(request)
    |> Repo.insert(session: session)
  end

  @doc """
  Updates a ledger_entry.

  Transitioning `status` to `:voided` causes the DB trigger to reverse the balance
  delta on the parent LedgerAccount and all ancestor accounts. Other status transitions
  (e.g. pending → posted) do not affect balances.

  ## Examples

      iex> update_ledger_entry(session, entry, %{status: :posted})
      {:ok, %LedgerEntry{}}

      iex> update_ledger_entry(session, entry, %{status: :voided})
      {:ok, %LedgerEntry{}}  # trigger reverses balance on account + all ancestors

  """
  @spec update_ledger_entry(Session.t(), LedgerEntry.t(), LedgerEntryRequest.t()) ::
          {:ok, LedgerEntry.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_ledger_entry(
                             session,
                             %LedgerEntry{} = ledger_entry,
                             %LedgerEntryRequest{} = request
                           ),
                           log_fields: [:ledger_entry] do
    ledger_entry
    |> LedgerEntry.changeset(request)
    |> Repo.update(session: session)
  end

  @doc """
  Deletes a ledger_entry.

  NOTE: Deleting a posted entry does NOT reverse the balance. Transition status to
  `:voided` first to reverse the balance, then delete if needed.

  ## Examples

      iex> delete_ledger_entry(session, ledger_entry)
      {:ok, %LedgerEntry{}}

  """
  @spec delete_ledger_entry(Session.t(), LedgerEntry.t()) ::
          {:ok, LedgerEntry.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_ledger_entry(session, %LedgerEntry{} = ledger_entry),
    log_fields: [:ledger_entry] do
    Repo.delete(ledger_entry, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking ledger_entry changes.

  ## Examples

      iex> change_ledger_entry(ledger_entry)
      %Ecto.Changeset{data: %LedgerEntry{}}

  """
  def change_ledger_entry(%LedgerEntry{} = ledger_entry, attrs \\ %{}) do
    LedgerEntry.changeset(ledger_entry, attrs)
  end
end
