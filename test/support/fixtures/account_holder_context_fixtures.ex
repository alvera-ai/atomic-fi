defmodule PaymentCompliancePlatform.AccountHolderContextFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `PaymentCompliancePlatform.AccountHolderContext` context.
  """

  @doc """
  Generate a account_holder.
  """
  def account_holder_fixture(attrs \\ %{}) do
    {:ok, account_holder} =
      attrs
      |> Enum.into(%{
        name: "some name",
        type: "some type"
      })
      |> PaymentCompliancePlatform.AccountHolderContext.create_account_holder()

    account_holder
  end
end
