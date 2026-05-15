defmodule AtomicFi.BeneficialOwnerContext do
  @moduledoc """
  The BeneficialOwnerContext context.

  Manages beneficial owners of corporate account holders per FinCEN CDD Rule
  31 CFR §1010.230 and FATF Recommendation 24. A beneficial owner is any person
  or entity that owns ≥25% of a company or exercises control over it.

  All PII lives in the linked LegalEntity — this context manages the ownership
  relationship and verification status only.
  """

  import Ecto.Query, warn: false
  use AtomicFi.LoggerMacro

  alias AtomicFi.BeneficialOwnerContext.BeneficialOwner
  alias AtomicFi.LedgerAccountContext
  alias AtomicFi.OnboardingContext
  alias AtomicFi.OpenApiSchema.BeneficialOwnerRequest
  alias AtomicFi.Repo
  alias AtomicFi.SessionContext.Session

  @preloads [legal_entity: [:addresses, :phone_numbers, :identifications]]

  @doc """
  Returns the list of beneficial_owners with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.

  ## Examples

      iex> list_beneficial_owners(session, %{page: 1, page_size: 20})
      {:ok, {[%BeneficialOwner{}, ...], %Flop.Meta{}}}

  """
  @spec list_beneficial_owners(Session.t(), map()) ::
          {:ok, {list(BeneficialOwner.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_beneficial_owners(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    BeneficialOwner
    |> preload_query()
    |> Flop.validate_and_run(flop_params,
      for: BeneficialOwner,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single beneficial_owner.

  Raises `Ecto.NoResultsError` if the BeneficialOwner does not exist.

  ## Examples

      iex> get_beneficial_owner!(session, "123")
      %BeneficialOwner{}

      iex> get_beneficial_owner!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_beneficial_owner!(Session.t(), Ecto.UUID.t()) :: BeneficialOwner.t()
  def_with_rls_and_logging get_beneficial_owner!(session, id), log_fields: [:id] do
    BeneficialOwner
    |> preload_query()
    |> Repo.get!(id, session: session)
  end

  @doc """
  Creates a beneficial_owner.

  ## Examples

      iex> create_beneficial_owner(session, %{field: value})
      {:ok, %BeneficialOwner{}}

      iex> create_beneficial_owner(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_beneficial_owner(Session.t(), BeneficialOwnerRequest.t()) ::
          {:ok, BeneficialOwner.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_beneficial_owner(
                             session,
                             %BeneficialOwnerRequest{} = request
                           ),
                           log_fields: [] do
    with {:ok, beneficial_owner} <-
           %BeneficialOwner{}
           |> BeneficialOwner.changeset(request)
           |> Repo.insert(session: session)
           |> bo_lifecycle(),
         {:ok, beneficial_owner} <- OnboardingContext.onboard(session, beneficial_owner) do
      {:ok, beneficial_owner}
    end
  end

  @doc """
  Updates a beneficial_owner.

  ## Examples

      iex> update_beneficial_owner(session, beneficial_owner, %{field: new_value})
      {:ok, %BeneficialOwner{}}

      iex> update_beneficial_owner(session, beneficial_owner, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_beneficial_owner(Session.t(), BeneficialOwner.t(), BeneficialOwnerRequest.t()) ::
          {:ok, BeneficialOwner.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_beneficial_owner(
                             session,
                             %BeneficialOwner{} = beneficial_owner,
                             %BeneficialOwnerRequest{} = request
                           ),
                           log_fields: [:beneficial_owner] do
    with {:ok, beneficial_owner} <-
           beneficial_owner
           |> BeneficialOwner.changeset(request)
           |> Repo.update(session: session)
           |> bo_lifecycle(),
         {:ok, beneficial_owner} <- OnboardingContext.onboard(session, beneficial_owner) do
      {:ok, beneficial_owner}
    end
  end

  @doc """
  `AtomicFi.ControlProtocol` callback for `%BeneficialOwner{}`.

  BOs have no LedgerAccounts of their own; the engine ran against the
  BO's parent (carried on `result.engine_entity`) and the returned
  controls target THAT entity's LAs. This impl applies controls to the
  engine_entity's LAs, enqueues + links the BO's own re-screen
  `OnboardingWorker` so the BO is periodically re-screened on its own
  schedule.
  """
  @spec process_controls(BeneficialOwner.t(), Session.t(), OnboardingContext.result()) ::
          {:ok, BeneficialOwner.t()} | {:error, term()}
  def process_controls(%BeneficialOwner{} = beneficial_owner, session, %{
        controls: controls,
        next_screening_at: next_screening_at,
        engine_entity: engine_entity
      }) do
    engine_entity_las = LedgerAccountContext.list_for_entity(session, engine_entity)

    with :ok <- LedgerAccountContext.apply_controls(session, engine_entity_las, controls),
         {:ok, job_id} <- OnboardingContext.enqueue_next(beneficial_owner, next_screening_at),
         {:ok, beneficial_owner} <-
           beneficial_owner
           |> Ecto.Changeset.change(%{rescreen_job_id: job_id})
           |> Repo.update(session: session) do
      {:ok, beneficial_owner}
    end
  end

  @doc """
  Deletes a beneficial_owner.

  ## Examples

      iex> delete_beneficial_owner(session, beneficial_owner)
      {:ok, %BeneficialOwner{}}

      iex> delete_beneficial_owner(session, beneficial_owner)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_beneficial_owner(Session.t(), BeneficialOwner.t()) ::
          {:ok, BeneficialOwner.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_beneficial_owner(
                             session,
                             %BeneficialOwner{} = beneficial_owner
                           ),
                           log_fields: [:beneficial_owner] do
    Repo.delete(beneficial_owner, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking beneficial_owner changes.

  ## Examples

      iex> change_beneficial_owner(beneficial_owner)
      %Ecto.Changeset{data: %BeneficialOwner{}}

  """
  def change_beneficial_owner(%BeneficialOwner{} = beneficial_owner, attrs \\ %{}) do
    BeneficialOwner.changeset(beneficial_owner, attrs)
  end

  # ── private: query + post-write lifecycle ────────────────────────────────

  defp preload_query(query), do: preload(query, ^@preloads)

  defp preload(%BeneficialOwner{} = bo) do
    Repo.preload(bo, @preloads, skip_multi_tenancy_check: true)
  end

  defp bo_lifecycle({:ok, %BeneficialOwner{} = bo}), do: {:ok, preload(bo)}
  defp bo_lifecycle({:error, _} = err), do: err
end
