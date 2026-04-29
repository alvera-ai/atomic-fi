defmodule AtomicFi.AccountHolderContext do
  @moduledoc """
  Account holder context — manages the MDM subjects that control accounts.

  AccountHolder records represent the operational state (status, KYC, risk level)
  while all PII lives in the linked LegalEntity.
  """

  import Ecto.Query, warn: false
  use AtomicFi.LoggerMacro

  alias AtomicFi.ComplianceScreeningContext.ScreeningWorker
  alias AtomicFi.OpenApiSchema.AccountHolderRequest
  alias AtomicFi.Repo
  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.SessionContext.Session

  @preloads [legal_entity: [:addresses, :phone_numbers, :identifications]]

  @doc """
  Returns the list of account_holders with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.

  ## Examples

      iex> list_account_holders(session, %{page: 1, page_size: 20})
      {:ok, {[%AccountHolder{}, ...], %Flop.Meta{}}}

  """
  @spec list_account_holders(Session.t(), map()) ::
          {:ok, {list(AccountHolder.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_account_holders(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    AccountHolder
    |> preload_query()
    |> Flop.validate_and_run(flop_params,
      for: AccountHolder,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single account_holder.

  Raises `Ecto.NoResultsError` if the Account holder does not exist.

  ## Examples

      iex> get_account_holder!(session, "123")
      %AccountHolder{}

      iex> get_account_holder!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_account_holder!(Session.t(), Ecto.UUID.t()) :: AccountHolder.t()
  def_with_rls_and_logging get_account_holder!(session, id), log_fields: [:id] do
    AccountHolder
    |> preload_query()
    |> Repo.get!(id, session: session)
  end

  @doc """
  Creates a account_holder.

  ## Examples

      iex> create_account_holder(session, %{field: value})
      {:ok, %AccountHolder{}}

      iex> create_account_holder(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_account_holder(Session.t(), AccountHolderRequest.t()) ::
          {:ok, AccountHolder.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_account_holder(
                             session,
                             %AccountHolderRequest{} = request
                           ),
                           log_fields: [] do
    result =
      %AccountHolder{}
      |> AccountHolder.changeset(request)
      |> Repo.insert(session: session)
      |> preload_after_write()

    with {:ok, account_holder} <- result do
      if request.chain_screening do
        %{
          subject: "account_holder",
          account_holder_id: account_holder.id,
          tenant_id: account_holder.tenant_id
        }
        |> ScreeningWorker.new()
        |> Oban.insert!()
      end

      {:ok, account_holder}
    end
  end

  @doc """
  Updates a account_holder.

  ## Examples

      iex> update_account_holder(session, account_holder, %{field: new_value})
      {:ok, %AccountHolder{}}

      iex> update_account_holder(session, account_holder, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_account_holder(Session.t(), AccountHolder.t(), AccountHolderRequest.t()) ::
          {:ok, AccountHolder.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_account_holder(
                             session,
                             %AccountHolder{} = account_holder,
                             %AccountHolderRequest{} = request
                           ),
                           log_fields: [:account_holder] do
    account_holder
    |> AccountHolder.changeset(request)
    |> Repo.update(session: session)
    |> preload_after_write()
  end

  @doc """
  Deletes a account_holder.

  ## Examples

      iex> delete_account_holder(session, account_holder)
      {:ok, %AccountHolder{}}

      iex> delete_account_holder(session, account_holder)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_account_holder(Session.t(), AccountHolder.t()) ::
          {:ok, AccountHolder.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_account_holder(session, %AccountHolder{} = account_holder),
    log_fields: [:account_holder] do
    Repo.delete(account_holder, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking account_holder changes.

  ## Examples

      iex> change_account_holder(account_holder)
      %Ecto.Changeset{data: %AccountHolder{}}

  """
  def change_account_holder(%AccountHolder{} = account_holder, attrs \\ %{}) do
    AccountHolder.changeset(account_holder, attrs)
  end

  # Pipes the preload into the query so Flop and Repo.get! always load associations.
  defp preload_query(query) do
    preload(query, ^@preloads)
  end

  # Preloads associations after successful write operations.
  # Uses skip_multi_tenancy_check since the record was just written and we need the full struct.
  defp preload_after_write({:ok, %AccountHolder{} = account_holder}) do
    {:ok, Repo.preload(account_holder, @preloads, skip_multi_tenancy_check: true)}
  end

  defp preload_after_write({:error, changeset}), do: {:error, changeset}
end
