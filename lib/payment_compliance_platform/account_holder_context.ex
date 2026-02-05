defmodule PaymentCompliancePlatform.AccountHolderContext do
  @moduledoc """
  The AccountHolderContext context.
  """

  import Ecto.Query, warn: false
  use PaymentCompliancePlatform.LoggerMacro

  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.AccountHolderContext.AccountHolder
  alias PaymentCompliancePlatform.SessionContext.Session

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
    Repo.get!(AccountHolder, id, session: session)
  end

  @doc """
  Creates a account_holder.

  ## Examples

      iex> create_account_holder(session, %{field: value})
      {:ok, %AccountHolder{}}

      iex> create_account_holder(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_account_holder(Session.t(), map()) ::
          {:ok, AccountHolder.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_account_holder(session, attrs), log_fields: [] do
    %AccountHolder{}
    |> AccountHolder.changeset(attrs)
    |> Repo.insert(session: session)
  end

  @doc """
  Updates a account_holder.

  ## Examples

      iex> update_account_holder(session, account_holder, %{field: new_value})
      {:ok, %AccountHolder{}}

      iex> update_account_holder(session, account_holder, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_account_holder(Session.t(), AccountHolder.t(), map()) ::
          {:ok, AccountHolder.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_account_holder(
                             session,
                             %AccountHolder{} = account_holder,
                             attrs
                           ),
                           log_fields: [:account_holder] do
    account_holder
    |> AccountHolder.changeset(attrs)
    |> Repo.update(session: session)
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
end
