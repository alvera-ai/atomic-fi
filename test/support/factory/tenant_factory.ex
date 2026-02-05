defmodule PaymentCompliancePlatform.Factory.TenantFactory do
  @moduledoc """
  Factory for Tenant context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias PaymentCompliancePlatform.TenantContext.Tenant

      def tenant_factory do
        unique_suffix = String.slice(Ecto.UUID.generate(), 0, 8)

        %Tenant{
          name: "Tenant #{unique_suffix}",
          slug: "tenant-#{unique_suffix}",
          status: :active,
          tenant_type: :standard,
          metadata: %{}
        }
      end
    end
  end
end
