defmodule AtomicFi.AccountActivitySnapshotContext do
  @moduledoc """
  AccountActivitySnapshot context — manages periodic activity summaries for AccountHolders.

  Each snapshot captures aggregated debit/credit counts and amounts for a specific
  reporting period, linked to an AccountHolder and optionally a PaymentAccount or
  LedgerAccount.

  ## ISO 20022 Alignment

  - `camt:052` — BankToCustomerAccountReport (intraday snapshots)
  - `camt:053` — BankToCustomerStatement (daily/weekly/monthly snapshots)

  The snapshot_type field distinguishes camt:052 (`:intraday`) from camt:053
  (`:daily`, `:weekly`, `:monthly`) reports.

  ## FinCEN AML — SAR Filing

  Snapshots with `flagged_for_review: true` surface account activity that has
  triggered AML thresholds. The `review_reason` explains the trigger and
  `sar_reference` records the SAR (Suspicious Activity Report) filing reference
  once submitted to FinCEN (31 CFR §1020.320).
  """

  import Ecto.Query, warn: false
  use AtomicFi.LoggerMacro

  alias AtomicFi.AccountActivitySnapshotContext.AccountActivitySnapshot
  alias AtomicFi.OpenApiSchema.AccountActivitySnapshotRequest
  alias AtomicFi.Repo
  alias AtomicFi.SessionContext.Session

  @doc """
  Returns the list of account activity snapshots with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.

  ## Examples

      iex> list_account_activity_snapshots(session, %{page: 1, page_size: 20})
      {:ok, {[%AccountActivitySnapshot{}, ...], %Flop.Meta{}}}

  """
  @spec list_account_activity_snapshots(Session.t(), map()) ::
          {:ok, {list(AccountActivitySnapshot.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_account_activity_snapshots(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    AccountActivitySnapshot
    |> Flop.validate_and_run(flop_params,
      for: AccountActivitySnapshot,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single account activity snapshot.

  Raises `Ecto.NoResultsError` if the AccountActivitySnapshot does not exist.

  ## Examples

      iex> get_account_activity_snapshot!(session, "123")
      %AccountActivitySnapshot{}

      iex> get_account_activity_snapshot!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_account_activity_snapshot!(Session.t(), Ecto.UUID.t()) :: AccountActivitySnapshot.t()
  def_with_rls_and_logging get_account_activity_snapshot!(session, id), log_fields: [:id] do
    Repo.get!(AccountActivitySnapshot, id, session: session)
  end

  @doc """
  Creates an account activity snapshot.

  ## Examples

      iex> create_account_activity_snapshot(session, %{field: value})
      {:ok, %AccountActivitySnapshot{}}

      iex> create_account_activity_snapshot(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_account_activity_snapshot(Session.t(), AccountActivitySnapshotRequest.t()) ::
          {:ok, AccountActivitySnapshot.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_account_activity_snapshot(
                             session,
                             %AccountActivitySnapshotRequest{} = request
                           ),
                           log_fields: [] do
    %AccountActivitySnapshot{}
    |> AccountActivitySnapshot.changeset(request)
    |> Repo.insert(session: session)
  end

  @doc """
  Updates an account activity snapshot.

  ## Examples

      iex> update_account_activity_snapshot(session, snapshot, %{field: new_value})
      {:ok, %AccountActivitySnapshot{}}

      iex> update_account_activity_snapshot(session, snapshot, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_account_activity_snapshot(
          Session.t(),
          AccountActivitySnapshot.t(),
          AccountActivitySnapshotRequest.t()
        ) :: {:ok, AccountActivitySnapshot.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_account_activity_snapshot(
                             session,
                             %AccountActivitySnapshot{} = snapshot,
                             %AccountActivitySnapshotRequest{} = request
                           ),
                           log_fields: [:snapshot] do
    snapshot
    |> AccountActivitySnapshot.changeset(request)
    |> Repo.update(session: session)
  end

  @doc """
  Deletes an account activity snapshot.

  ## Examples

      iex> delete_account_activity_snapshot(session, snapshot)
      {:ok, %AccountActivitySnapshot{}}

      iex> delete_account_activity_snapshot(session, snapshot)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_account_activity_snapshot(Session.t(), AccountActivitySnapshot.t()) ::
          {:ok, AccountActivitySnapshot.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_account_activity_snapshot(
                             session,
                             %AccountActivitySnapshot{} = snapshot
                           ),
                           log_fields: [:snapshot] do
    Repo.delete(snapshot, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking account activity snapshot changes.

  ## Examples

      iex> change_account_activity_snapshot(snapshot)
      %Ecto.Changeset{data: %AccountActivitySnapshot{}}

  """
  def change_account_activity_snapshot(
        %AccountActivitySnapshot{} = snapshot,
        attrs \\ %{}
      ) do
    AccountActivitySnapshot.changeset(snapshot, attrs)
  end
end
