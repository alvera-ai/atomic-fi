defmodule AtomicFi.LegalEntityContextFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `AtomicFi.LegalEntityContext` context.
  """

  import AtomicFi.Factory

  @doc """
  Generate a legal_entity.
  """
  def legal_entity_fixture(attrs \\ %{}) do
    insert(:legal_entity, attrs)
  end
end
