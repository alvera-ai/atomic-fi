defmodule PaymentCompliancePlatform.Factory.CounterpartyFactory do
  @moduledoc """
  Factory for Counterparty context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias PaymentCompliancePlatform.CounterpartyContext.Counterparty

      def counterparty_factory(attrs \\ %{}) do
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

        %Counterparty{
          account_holder_id: account_holder_id,
          legal_entity_id: legal_entity_id,
          status: :active,
          tenant_id: tenant_id
        }
        |> merge_attributes(attrs)
        |> evaluate_lazy_attributes()
      end
    end
  end
end
