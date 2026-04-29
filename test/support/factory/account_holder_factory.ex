defmodule AtomicFi.Factory.AccountHolderFactory do
  @moduledoc """
  Factory for AccountHolder context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.AccountHolderContext.AccountHolder

      def account_holder_factory(attrs \\ %{}) do
        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        legal_entity_id =
          Map.get_lazy(attrs, :legal_entity_id, fn ->
            insert(:legal_entity, tenant_id: tenant_id).id
          end)

        %AccountHolder{
          legal_entity_id: legal_entity_id,
          holder_type: :individual,
          status: :pending,
          kyc_status: :not_started,
          risk_level: :low,
          enabled_currencies: ["USD"],
          tenant_id: tenant_id
        }
        |> merge_attributes(attrs)
        |> evaluate_lazy_attributes()
      end
    end
  end
end
