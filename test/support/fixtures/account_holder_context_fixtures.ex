defmodule PaymentCompliancePlatform.AccountHolderContextFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `PaymentCompliancePlatform.AccountHolderContext` context.
  """

  import PaymentCompliancePlatform.DataCase, only: [system_session: 0]

  @doc """
  Generate a account_holder.
  """
  def account_holder_fixture(attrs \\ %{}) do
    session = system_session()

    {:ok, account_holder} =
      attrs
      |> Enum.into(%{
        name: "some name",
        type: :individual,
        tenant_id: session.tenant_id
      })
      |> then(&PaymentCompliancePlatform.AccountHolderContext.create_account_holder(session, &1))

    account_holder
  end
end
