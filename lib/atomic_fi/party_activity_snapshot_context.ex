defmodule AtomicFi.PartyActivitySnapshotContext do
  @moduledoc """
  PartyActivitySnapshot context — manages period-level AML monitoring summaries
  for AccountHolders.

  Distinct from `AccountActivitySnapshotContext`:
  - AccountActivitySnapshot aggregates ledger activity (camt:052/camt:053) for
    a specific PaymentAccount.
  - PartyActivitySnapshot aggregates party-level compliance signals
    (KYC/risk transitions, screening volume, SAR candidacy) across a period.

  Supports FATF Recommendation 10 (ongoing CDD) and FinCEN 31 CFR §1020.320
  (SAR filing) workflows.
  """

  import Ecto.Query, warn: false
  use AtomicFi.LoggerMacro

  alias AtomicFi.OpenApiSchema.PartyActivitySnapshotRequest
  alias AtomicFi.PartyActivitySnapshotContext.PartyActivitySnapshot
  alias AtomicFi.Repo
  alias AtomicFi.SessionContext.Session

  @doc """
  Returns the list of party activity snapshots with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.

  ## Examples

      iex> list_party_activity_snapshots(session, %{page: 1, page_size: 20})
      {:ok, {[%PartyActivitySnapshot{}, ...], %Flop.Meta{}}}

  """
  @spec list_party_activity_snapshots(Session.t(), map()) ::
          {:ok, {list(PartyActivitySnapshot.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_party_activity_snapshots(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    PartyActivitySnapshot
    |> Flop.validate_and_run(flop_params,
      for: PartyActivitySnapshot,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single party activity snapshot.

  Raises `Ecto.NoResultsError` if the PartyActivitySnapshot does not exist.
  """
  @spec get_party_activity_snapshot!(Session.t(), Ecto.UUID.t()) :: PartyActivitySnapshot.t()
  def_with_rls_and_logging get_party_activity_snapshot!(session, id), log_fields: [:id] do
    Repo.get!(PartyActivitySnapshot, id, session: session)
  end

  @doc """
  Creates a party activity snapshot.
  """
  @spec create_party_activity_snapshot(Session.t(), PartyActivitySnapshotRequest.t()) ::
          {:ok, PartyActivitySnapshot.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_party_activity_snapshot(
                             session,
                             %PartyActivitySnapshotRequest{} = request
                           ),
                           log_fields: [] do
    %PartyActivitySnapshot{}
    |> PartyActivitySnapshot.changeset(request)
    |> Repo.insert(session: session)
  end

  @doc """
  Updates a party activity snapshot.
  """
  @spec update_party_activity_snapshot(
          Session.t(),
          PartyActivitySnapshot.t(),
          PartyActivitySnapshotRequest.t()
        ) :: {:ok, PartyActivitySnapshot.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_party_activity_snapshot(
                             session,
                             %PartyActivitySnapshot{} = snapshot,
                             %PartyActivitySnapshotRequest{} = request
                           ),
                           log_fields: [:snapshot] do
    snapshot
    |> PartyActivitySnapshot.changeset(request)
    |> Repo.update(session: session)
  end

  @doc """
  Deletes a party activity snapshot.
  """
  @spec delete_party_activity_snapshot(Session.t(), PartyActivitySnapshot.t()) ::
          {:ok, PartyActivitySnapshot.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_party_activity_snapshot(
                             session,
                             %PartyActivitySnapshot{} = snapshot
                           ),
                           log_fields: [:snapshot] do
    Repo.delete(snapshot, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking party activity snapshot changes.
  """
  def change_party_activity_snapshot(%PartyActivitySnapshot{} = snapshot, attrs \\ %{}) do
    PartyActivitySnapshot.changeset(snapshot, attrs)
  end
end
