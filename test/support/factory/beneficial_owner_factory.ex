defmodule PaymentCompliancePlatform.Factory.BeneficialOwnerFactory do
  @moduledoc """
  Factory for BeneficialOwner context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias PaymentCompliancePlatform.BeneficialOwnerContext.BeneficialOwner

      def beneficial_owner_factory(attrs \\ %{}) do
        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        account_holder_id =
          Map.get_lazy(attrs, :account_holder_id, fn ->
            insert(:account_holder, tenant_id: tenant_id).id
          end)

        legal_entity_id =
          Map.get_lazy(attrs, :legal_entity_id, fn ->
            insert(:legal_entity, tenant_id: tenant_id).id
          end)

        %BeneficialOwner{
          account_holder_id: account_holder_id,
          legal_entity_id: legal_entity_id,
          ownership_pct: 25.0,
          control_type: :shareholder,
          verification_status: :pending,
          tenant_id: tenant_id
        }
      end
    end
  end
end
