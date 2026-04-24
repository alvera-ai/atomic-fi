defmodule PaymentCompliancePlatform.Factory.PartyActivitySnapshotFactory do
  @moduledoc """
  Factory for PartyActivitySnapshot context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias PaymentCompliancePlatform.PartyActivitySnapshotContext.PartyActivitySnapshot

      def party_activity_snapshot_factory(attrs \\ %{}) do
        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        account_holder_id =
          Map.get_lazy(attrs, :account_holder_id, fn ->
            insert(:account_holder, tenant_id: tenant_id).id
          end)

        today = Date.utc_today()
        period_start = Map.get_lazy(attrs, :period_start, fn -> Date.add(today, -30) end)
        period_end = Map.get_lazy(attrs, :period_end, fn -> today end)

        %PartyActivitySnapshot{
          account_holder_id: account_holder_id,
          period_type: :monthly,
          period_start: period_start,
          period_end: period_end,
          kyc_status_at_start: :approved,
          kyc_status_at_end: :approved,
          risk_level_at_start: :low,
          risk_level_at_end: :low,
          total_screenings: 0,
          screening_hits: 0,
          transaction_count: 0,
          total_debit_amount: 0,
          total_credit_amount: 0,
          high_risk_transaction_count: 0,
          sar_indicator: false,
          tenant_id: tenant_id
        }
        |> merge_attributes(attrs)
        |> evaluate_lazy_attributes()
      end
    end
  end
end
