defmodule AtomicFi.Factory.RoleFactory do
  @moduledoc """
  Factory for Role context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.RoleContext.Role

      def role_factory(attrs \\ %{}) do
        unique_suffix = String.slice(Ecto.UUID.generate(), 0, 8)

        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        %Role{
          name: "role-#{unique_suffix}",
          description: "Role description for #{unique_suffix}",
          metadata: %{},
          tenant_id: tenant_id
        }
      end
    end
  end
end
