defmodule AtomicFi.LedgerAccountContext do
  @moduledoc """
  LedgerAccount context — manages chart-of-accounts line items within a Ledger.

  LedgerAccount.balance is a running total in minor currency units (e.g. cents for USD).
  It is updated atomically by the `ledger_entry_propagate_to_balances` PostgreSQL trigger
  whenever a LedgerEntry is inserted or voided.

  LedgerAccounts are hierarchical. The `ancestor_ids` array is a flat
  root-first path of ancestor UUIDs — the single source of truth for
  hierarchy traversal (no separate parent_id column). Callers set
  `ancestor_ids` explicitly on insert/update via the changeset.

  The `ledger_entry_propagate_to_balances` trigger walks `ancestor_ids` so
  cumulative balances roll up through the account hierarchy automatically.
  """

  import Ecto.Query, warn: false
  use AtomicFi.LoggerMacro

  alias AtomicFi.OpenApiSchema.LedgerAccountRequest
  alias AtomicFi.Repo
  alias AtomicFi.LedgerAccountContext.LedgerAccount
  alias AtomicFi.SessionContext.Session

  # Default preload set — the linked_ledger_accounts edge list (with each edge's
  # target LA hydrated) is the read-side ergonomic for tree traversal. Single
  # source of truth: callers never reach into Repo / Ecto.Query themselves.
  @preloads [linked_ledger_accounts: :to]

  @doc """
  Returns the list of ledger_accounts with pagination and filtering.

  ## Examples

      iex> list_ledger_accounts(session, %{page: 1, page_size: 20})
      {:ok, {[%LedgerAccount{}, ...], %Flop.Meta{}}}

  """
  @spec list_ledger_accounts(Session.t(), map()) ::
          {:ok, {list(LedgerAccount.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_ledger_accounts(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    with {:ok, {accounts, meta}} <-
           LedgerAccount
           |> Flop.validate_and_run(flop_params,
             for: LedgerAccount,
             repo: Repo,
             query_opts: [session: session]
           ) do
      {:ok, {Repo.preload(accounts, @preloads, session: session), meta}}
    end
  end

  @doc """
  Gets a single ledger_account.

  Raises `Ecto.NoResultsError` if the LedgerAccount does not exist.

  ## Examples

      iex> get_ledger_account!(session, "123")
      %LedgerAccount{}

      iex> get_ledger_account!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_ledger_account!(Session.t(), Ecto.UUID.t()) :: LedgerAccount.t()
  def_with_rls_and_logging get_ledger_account!(session, id), log_fields: [:id] do
    LedgerAccount
    |> Repo.get!(id, session: session)
    |> Repo.preload(@preloads, session: session)
  end

  @doc """
  Creates a ledger_account.

  Callers supply `ancestor_ids` directly on the request (root-first list of
  parent LA UUIDs). Root LAs use `ancestor_ids: []`.

  ## Examples

      iex> create_ledger_account(session, %{field: value})
      {:ok, %LedgerAccount{}}

      iex> create_ledger_account(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_ledger_account(Session.t(), LedgerAccountRequest.t()) ::
          {:ok, LedgerAccount.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_ledger_account(session, %LedgerAccountRequest{} = request),
    log_fields: [] do
    with {:ok, ledger_account} <-
           %LedgerAccount{}
           |> LedgerAccount.changeset(request)
           |> Repo.insert(session: session) do
      {:ok, Repo.preload(ledger_account, @preloads, session: session)}
    end
  end

  @doc """
  Updates a ledger_account.

  NOTE: balance is never updated directly through this function.
  LedgerEntry inserts and voids update balances via the DB trigger.

  ## Examples

      iex> update_ledger_account(session, ledger_account, %{field: new_value})
      {:ok, %LedgerAccount{}}

      iex> update_ledger_account(session, ledger_account, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_ledger_account(Session.t(), LedgerAccount.t(), LedgerAccountRequest.t()) ::
          {:ok, LedgerAccount.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_ledger_account(
                             session,
                             %LedgerAccount{} = ledger_account,
                             %LedgerAccountRequest{} = request
                           ),
                           log_fields: [:ledger_account] do
    with {:ok, updated} <-
           ledger_account
           |> LedgerAccount.changeset(request)
           |> Repo.update(session: session) do
      {:ok, Repo.preload(updated, @preloads, session: session)}
    end
  end

  @doc """
  Deletes a ledger_account.

  ## Examples

      iex> delete_ledger_account(session, ledger_account)
      {:ok, %LedgerAccount{}}

      iex> delete_ledger_account(session, ledger_account)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_ledger_account(Session.t(), LedgerAccount.t()) ::
          {:ok, LedgerAccount.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_ledger_account(session, %LedgerAccount{} = ledger_account),
    log_fields: [:ledger_account] do
    Repo.delete(ledger_account, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking ledger_account changes.

  ## Examples

      iex> change_ledger_account(ledger_account)
      %Ecto.Changeset{data: %LedgerAccount{}}

  """
  def change_ledger_account(%LedgerAccount{} = ledger_account, attrs \\ %{}) do
    LedgerAccount.changeset(ledger_account, attrs)
  end
end
