defmodule PaymentCompliancePlatform.AccountHolderContext do
  @moduledoc """
  The AccountHolderContext context.
  """

  import Ecto.Query, warn: false
  alias PaymentCompliancePlatform.Repo

  alias PaymentCompliancePlatform.AccountHolderContext.AccountHolder

  @doc """
  Returns the list of account_holders.

  ## Examples

      iex> list_account_holders()
      [%AccountHolder{}, ...]

  """
  def list_account_holders do
    Repo.all(AccountHolder)
  end

  @doc """
  Gets a single account_holder.

  Raises `Ecto.NoResultsError` if the Account holder does not exist.

  ## Examples

      iex> get_account_holder!(123)
      %AccountHolder{}

      iex> get_account_holder!(456)
      ** (Ecto.NoResultsError)

  """
  def get_account_holder!(id), do: Repo.get!(AccountHolder, id)

  @doc """
  Creates a account_holder.

  ## Examples

      iex> create_account_holder(%{field: value})
      {:ok, %AccountHolder{}}

      iex> create_account_holder(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_account_holder(attrs) do
    %AccountHolder{}
    |> AccountHolder.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a account_holder.

  ## Examples

      iex> update_account_holder(account_holder, %{field: new_value})
      {:ok, %AccountHolder{}}

      iex> update_account_holder(account_holder, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_account_holder(%AccountHolder{} = account_holder, attrs) do
    account_holder
    |> AccountHolder.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a account_holder.

  ## Examples

      iex> delete_account_holder(account_holder)
      {:ok, %AccountHolder{}}

      iex> delete_account_holder(account_holder)
      {:error, %Ecto.Changeset{}}

  """
  def delete_account_holder(%AccountHolder{} = account_holder) do
    Repo.delete(account_holder)
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
