defmodule PaymentCompliancePlatform.Factory.LegalEntityChangeEventFactory do
  @moduledoc """
  Factory for LegalEntityChangeEvent context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias PaymentCompliancePlatform.LegalEntityChangeEventContext.LegalEntityChangeEvent

      def legal_entity_change_event_factory(attrs \\ %{}) do
        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        legal_entity_id =
          Map.get_lazy(attrs, :legal_entity_id, fn ->
            insert(:legal_entity, tenant_id: tenant_id).id
          end)

        %LegalEntityChangeEvent{
          event_type: :address_change,
          change_channel: :web,
          event_status: :pending,
          legal_entity_id: legal_entity_id,
          tenant_id: tenant_id
        }
        |> merge_attributes(attrs)
        |> evaluate_lazy_attributes()
      end
    end
  end
end
