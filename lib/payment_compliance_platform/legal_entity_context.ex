defmodule PaymentCompliancePlatform.LegalEntityContext do
  @moduledoc """
  The LegalEntityContext context.

  Manages shared identity records for individuals and businesses per ISO 20022 acmt:007 + FATF CDD.
  LegalEntity is the foundational identity layer — domain-specific overlays (KYC status, risk level)
  belong on the MDM subject (AccountHolder, etc.).
  """

  import Ecto.Query, warn: false
  use PaymentCompliancePlatform.LoggerMacro

  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.LegalEntityContext.LegalEntity
  alias PaymentCompliancePlatform.SessionContext.Session

  @legal_entity_preloads [:addresses, :phone_numbers, :identifications]

  @doc """
  Returns the list of legal_entities with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.

  ## Examples

      iex> list_legal_entities(session, %{page: 1, page_size: 20})
      {:ok, {[%LegalEntity{}, ...], %Flop.Meta{}}}

  """
  @spec list_legal_entities(Session.t(), map()) ::
          {:ok, {list(LegalEntity.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_legal_entities(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    LegalEntity
    |> preload(^@legal_entity_preloads)
    |> Flop.validate_and_run(flop_params,
      for: LegalEntity,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single legal_entity with preloaded associations.

  Raises `Ecto.NoResultsError` if the Legal entity does not exist.

  ## Examples

      iex> get_legal_entity!(session, "123")
      %LegalEntity{}

      iex> get_legal_entity!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_legal_entity!(Session.t(), Ecto.UUID.t()) :: LegalEntity.t()
  def_with_rls_and_logging get_legal_entity!(session, id), log_fields: [:id] do
    LegalEntity
    |> preload(^@legal_entity_preloads)
    |> Repo.get!(id, session: session)
  end

  @doc """
  Creates a legal_entity.

  Supports nested associations: addresses, phone_numbers, identifications can be
  provided as lists in attrs and will be created via cast_assoc.

  ## Examples

      iex> create_legal_entity(session, %{legal_entity_type: :individual, first_name: "John"})
      {:ok, %LegalEntity{}}

      iex> create_legal_entity(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_legal_entity(Session.t(), map()) ::
          {:ok, LegalEntity.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_legal_entity(session, attrs), log_fields: [] do
    %LegalEntity{}
    |> LegalEntity.changeset(attrs)
    |> Repo.insert(session: session)
    |> preload_after_write()
  end

  @doc """
  Updates a legal_entity.

  ## Examples

      iex> update_legal_entity(session, legal_entity, %{first_name: "Jane"})
      {:ok, %LegalEntity{}}

      iex> update_legal_entity(session, legal_entity, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_legal_entity(Session.t(), LegalEntity.t(), map()) ::
          {:ok, LegalEntity.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_legal_entity(
                             session,
                             %LegalEntity{} = legal_entity,
                             attrs
                           ),
                           log_fields: [:legal_entity] do
    legal_entity
    |> Repo.preload(@legal_entity_preloads, session: session)
    |> LegalEntity.changeset(attrs)
    |> Repo.update(session: session)
    |> preload_after_write()
  end

  @doc """
  Deletes a legal_entity.

  ## Examples

      iex> delete_legal_entity(session, legal_entity)
      {:ok, %LegalEntity{}}

      iex> delete_legal_entity(session, legal_entity)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_legal_entity(Session.t(), LegalEntity.t()) ::
          {:ok, LegalEntity.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_legal_entity(session, %LegalEntity{} = legal_entity),
    log_fields: [:legal_entity] do
    Repo.delete(legal_entity, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking legal_entity changes.

  ## Examples

      iex> change_legal_entity(legal_entity)
      %Ecto.Changeset{data: %LegalEntity{}}

  """
  def change_legal_entity(%LegalEntity{} = legal_entity, attrs \\ %{}) do
    LegalEntity.changeset(legal_entity, attrs)
  end

  # Private: Preload associations after writes
  defp preload_after_write({:ok, %LegalEntity{} = legal_entity}) do
    {:ok, Repo.preload(legal_entity, @legal_entity_preloads, skip_multi_tenancy_check: true)}
  end

  defp preload_after_write({:error, changeset}), do: {:error, changeset}
end
