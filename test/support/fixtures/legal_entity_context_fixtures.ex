defmodule PaymentCompliancePlatform.LegalEntityContextFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `PaymentCompliancePlatform.LegalEntityContext` context.
  """

  import PaymentCompliancePlatform.Factory

  @doc """
  Generate a legal_entity.
  """
  def legal_entity_fixture(attrs \\ %{}) do
    insert(:legal_entity, attrs)
  end
end
