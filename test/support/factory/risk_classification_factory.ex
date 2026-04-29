defmodule AtomicFi.Factory.RiskClassificationFactory do
  @moduledoc """
  Factory for RiskClassification context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.RiskClassificationContext.RiskClassification

      def risk_classification_factory(attrs \\ %{}) do
        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        account_holder_id =
          Map.get_lazy(attrs, :account_holder_id, fn ->
            insert(:account_holder, tenant_id: tenant_id).id
          end)

        %RiskClassification{
          account_holder_id: account_holder_id,
          risk_level: :low,
          classification_reason: "Initial classification",
          effective_from: Date.utc_today(),
          is_active: true,
          tenant_id: tenant_id
        }
        |> merge_attributes(attrs)
        |> evaluate_lazy_attributes()
      end
    end
  end
end
