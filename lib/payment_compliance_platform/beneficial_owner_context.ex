defmodule PaymentCompliancePlatform.BeneficialOwnerContext do
  @moduledoc """
  The BeneficialOwnerContext context.

  Manages beneficial owners of corporate account holders per FinCEN CDD Rule
  31 CFR §1010.230 and FATF Recommendation 24. A beneficial owner is any person
  or entity that owns ≥25% of a company or exercises control over it.

  All PII lives in the linked LegalEntity — this context manages the ownership
  relationship and verification status only.
  """

  import Ecto.Query, warn: false
  use PaymentCompliancePlatform.LoggerMacro

  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.BeneficialOwnerContext.BeneficialOwner
  alias PaymentCompliancePlatform.SessionContext.Session

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
    Repo.get!(BeneficialOwner, id, session: session)
  end

  @doc """
  Creates a beneficial_owner.

  ## Examples

      iex> create_beneficial_owner(session, %{field: value})
      {:ok, %BeneficialOwner{}}

      iex> create_beneficial_owner(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_beneficial_owner(Session.t(), map()) ::
          {:ok, BeneficialOwner.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_beneficial_owner(session, attrs), log_fields: [] do
    %BeneficialOwner{}
    |> BeneficialOwner.changeset(attrs)
    |> Repo.insert(session: session)
  end

  @doc """
  Updates a beneficial_owner.

  ## Examples

      iex> update_beneficial_owner(session, beneficial_owner, %{field: new_value})
      {:ok, %BeneficialOwner{}}

      iex> update_beneficial_owner(session, beneficial_owner, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_beneficial_owner(Session.t(), BeneficialOwner.t(), map()) ::
          {:ok, BeneficialOwner.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_beneficial_owner(
                             session,
                             %BeneficialOwner{} = beneficial_owner,
                             attrs
                           ),
                           log_fields: [:beneficial_owner] do
    beneficial_owner
    |> BeneficialOwner.changeset(attrs)
    |> Repo.update(session: session)
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
end
