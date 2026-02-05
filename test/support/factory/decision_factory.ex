defmodule PaymentCompliancePlatform.Factory.DecisionFactory do
  @moduledoc """
  Factory for Decision context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias PaymentCompliancePlatform.DecisionContext.Decision

      def decision_factory do
        %Decision{
          account_holder_id: Ecto.UUID.generate(),
          overall_status: "pass",
          total_entities_screened: 0,
          entities_with_matches: 0,
          list_synced_at: DateTime.utc_now(),
          list_sources: [],
          raw_request: %{},
          entity_decisions: [],
          tenant: build(:tenant)
        }
      end
    end
  end
end
