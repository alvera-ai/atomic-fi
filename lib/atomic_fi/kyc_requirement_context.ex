defmodule AtomicFi.KycRequirementContext do
  @moduledoc """
  KYC requirement context — manages per-party-type compliance verification requirements.

  One row per KYC verification action, classified by FATF scope:
  - `:account_holder` — CDD (FATF Rec 10); gates AccountHolder activation
  - `:counterparty` — EDD (FATF Rec 19); gates Counterparty activation
  - `:payment_account` — wire transfer (FATF Rec 16); gates PaymentAccount
  - `:beneficial_owner` — UBO transparency (FATF Rec 24); gates UBO chain

  The two-field anchor pattern: `account_holder_id` is always the MDM subject;
  `legal_entity_id` is the identity being verified.
  """

  import Ecto.Query, warn: false
  use AtomicFi.LoggerMacro

  alias AtomicFi.OpenApiSchema.KycRequirementRequest
  alias AtomicFi.Repo
  alias AtomicFi.KycRequirementContext.KycRequirement
  alias AtomicFi.SessionContext.Session

  @doc """
  Returns the list of kyc_requirements with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.

  ## Examples

      iex> list_kyc_requirements(session, %{page: 1, page_size: 20})
      {:ok, {[%KycRequirement{}, ...], %Flop.Meta{}}}

  """
  @spec list_kyc_requirements(Session.t(), map()) ::
          {:ok, {list(KycRequirement.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_kyc_requirements(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    KycRequirement
    |> Flop.validate_and_run(flop_params,
      for: KycRequirement,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single kyc_requirement.

  Raises `Ecto.NoResultsError` if the KycRequirement does not exist.

  ## Examples

      iex> get_kyc_requirement!(session, "123")
      %KycRequirement{}

      iex> get_kyc_requirement!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_kyc_requirement!(Session.t(), Ecto.UUID.t()) :: KycRequirement.t()
  def_with_rls_and_logging get_kyc_requirement!(session, id), log_fields: [:id] do
    Repo.get!(KycRequirement, id, session: session)
  end

  @doc """
  Creates a kyc_requirement.

  ## Examples

      iex> create_kyc_requirement(session, %{field: value})
      {:ok, %KycRequirement{}}

      iex> create_kyc_requirement(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_kyc_requirement(Session.t(), KycRequirementRequest.t()) ::
          {:ok, KycRequirement.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_kyc_requirement(
                             session,
                             %KycRequirementRequest{} = request
                           ),
                           log_fields: [] do
    %KycRequirement{}
    |> KycRequirement.changeset(request)
    |> Repo.insert(session: session)
  end

  @doc """
  Updates a kyc_requirement.

  ## Examples

      iex> update_kyc_requirement(session, kyc_requirement, %{field: new_value})
      {:ok, %KycRequirement{}}

      iex> update_kyc_requirement(session, kyc_requirement, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_kyc_requirement(Session.t(), KycRequirement.t(), KycRequirementRequest.t()) ::
          {:ok, KycRequirement.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_kyc_requirement(
                             session,
                             %KycRequirement{} = kyc_requirement,
                             %KycRequirementRequest{} = request
                           ),
                           log_fields: [:kyc_requirement] do
    kyc_requirement
    |> KycRequirement.changeset(request)
    |> Repo.update(session: session)
  end

  @doc """
  Deletes a kyc_requirement.

  ## Examples

      iex> delete_kyc_requirement(session, kyc_requirement)
      {:ok, %KycRequirement{}}

      iex> delete_kyc_requirement(session, kyc_requirement)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_kyc_requirement(Session.t(), KycRequirement.t()) ::
          {:ok, KycRequirement.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_kyc_requirement(session, %KycRequirement{} = kyc_requirement),
    log_fields: [:kyc_requirement] do
    Repo.delete(kyc_requirement, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking kyc_requirement changes.

  ## Examples

      iex> change_kyc_requirement(kyc_requirement)
      %Ecto.Changeset{data: %KycRequirement{}}

  """
  def change_kyc_requirement(%KycRequirement{} = kyc_requirement, attrs \\ %{}) do
    KycRequirement.changeset(kyc_requirement, attrs)
  end
end
