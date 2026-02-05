defmodule PaymentCompliancePlatform.Factory.CustomerFactory do
  @moduledoc """
  Factory for Customer context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias PaymentCompliancePlatform.CustomerContext.Customer

      def customer_factory(attrs \\ %{}) do
        unique_suffix = String.slice(Ecto.UUID.generate(), 0, 8)

        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        %Customer{
          name: "Customer #{unique_suffix}",
          slug: "customer-#{unique_suffix}",
          status: "active",
          description: "Customer description for #{unique_suffix}",
          metadata: %{},
          tenant_id: tenant_id
        }
      end
    end
  end
end
