defmodule AtomicFi.LedgerAccountContext do
  @moduledoc """
  LedgerAccount context — manages chart-of-accounts line items within a Ledger.

  LedgerAccount.balance is a running total in minor currency units (e.g. cents for USD).
  It is updated atomically by the `ledger_entry_propagate_to_balances` PostgreSQL trigger
  whenever a LedgerEntry is inserted or voided.

  LedgerAccounts are hierarchical via `parent_ledger_account_id`. The `ancestor_ids`
  array field is a materialized path of all ancestor UUIDs, computed and stored by this
  context at create/update time for O(1) descendant lookups.

  The trigger propagates entry effects to all ancestor balance rows (via ancestor_ids)
  so cumulative balances roll up through the account hierarchy automatically.
  """

  import Ecto.Query, warn: false
  use AtomicFi.LoggerMacro

  alias AtomicFi.OpenApiSchema.LedgerAccountRequest
  alias AtomicFi.Repo
  alias AtomicFi.LedgerAccountContext.LedgerAccount
  alias AtomicFi.SessionContext.Session

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
    LedgerAccount
    |> Flop.validate_and_run(flop_params,
      for: LedgerAccount,
      repo: Repo,
      query_opts: [session: session]
    )
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
    Repo.get!(LedgerAccount, id, session: session)
  end

  @doc """
  Creates a ledger_account.

  If `parent_ledger_account_id` is provided, the parent's `ancestor_ids` are fetched
  and the new account's `ancestor_ids` is set to `parent.ancestor_ids ++ [parent_id]`.
  Root accounts (no parent) have `ancestor_ids: []`.

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
    ancestor_ids = compute_ancestor_ids(session, request.parent_ledger_account_id)

    %LedgerAccount{ancestor_ids: ancestor_ids}
    |> LedgerAccount.changeset(request)
    |> Repo.insert(session: session)
  end

  @doc """
  Updates a ledger_account.

  If `parent_ledger_account_id` changes, `ancestor_ids` is recomputed from the new parent.

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
    ancestor_ids =
      if request.parent_ledger_account_id != ledger_account.parent_ledger_account_id do
        compute_ancestor_ids(session, request.parent_ledger_account_id)
      else
        ledger_account.ancestor_ids
      end

    ledger_account
    |> Map.put(:ancestor_ids, ancestor_ids)
    |> LedgerAccount.changeset(request)
    |> Repo.update(session: session)
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

  # Builds the ancestor_ids array for a new or reparented account.
  # parent_id = nil → root account → []
  # parent_id set → fetch parent's ancestor_ids and append parent_id
  defp compute_ancestor_ids(_session, nil), do: []

  defp compute_ancestor_ids(session, parent_id) do
    parent = Repo.get!(LedgerAccount, parent_id, session: session)
    (parent.ancestor_ids || []) ++ [parent_id]
  end
end
