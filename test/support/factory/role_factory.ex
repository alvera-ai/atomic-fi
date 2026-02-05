defmodule PaymentCompliancePlatform.Factory.RoleFactory do
  @moduledoc """
  Factory for Role context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias PaymentCompliancePlatform.RoleContext.Role

      def role_factory(attrs \\ %{}) do
        unique_suffix = String.slice(Ecto.UUID.generate(), 0, 8)

        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        customer_id = Map.get(attrs, :customer_id, nil)

        %Role{
          name: "role-#{unique_suffix}",
          description: "Role description for #{unique_suffix}",
          metadata: %{},
          tenant_id: tenant_id,
          customer_id: customer_id
        }
      end
    end
  end
end
