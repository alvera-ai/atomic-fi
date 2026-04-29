defmodule AtomicFi.AccountHolderContextFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `AtomicFi.AccountHolderContext` context.
  """

  import AtomicFi.Factory

  @doc """
  Generate an account_holder.
  """
  def account_holder_fixture(attrs \\ %{}) do
    insert(:account_holder, attrs)
  end
end
