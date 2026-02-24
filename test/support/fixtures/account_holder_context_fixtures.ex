defmodule PaymentCompliancePlatform.AccountHolderContextFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `PaymentCompliancePlatform.AccountHolderContext` context.
  """

  import PaymentCompliancePlatform.Factory

  @doc """
  Generate an account_holder.
  """
  def account_holder_fixture(attrs \\ %{}) do
    insert(:account_holder, attrs)
  end
end
