defmodule AtomicFi.Factory.AccountActivitySnapshotFactory do
  @moduledoc """
  Factory for AccountActivitySnapshot context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.AccountActivitySnapshotContext.AccountActivitySnapshot

      def account_activity_snapshot_factory(attrs \\ %{}) do
        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        account_holder_id =
          Map.get_lazy(attrs, :account_holder_id, fn ->
            insert(:account_holder, tenant_id: tenant_id).id
          end)

        now = DateTime.utc_now()

        period_start =
          Map.get_lazy(attrs, :period_start, fn -> DateTime.add(now, -86_400, :second) end)

        period_end = Map.get_lazy(attrs, :period_end, fn -> now end)

        %AccountActivitySnapshot{
          snapshot_type: :daily,
          period_start: period_start,
          period_end: period_end,
          status: :pending,
          total_debit_count: 0,
          total_credit_count: 0,
          total_debit_amount: 0,
          total_credit_amount: 0,
          transaction_count: 0,
          flagged_for_review: false,
          account_holder_id: account_holder_id,
          tenant_id: tenant_id
        }
        |> merge_attributes(attrs)
        |> evaluate_lazy_attributes()
      end
    end
  end
end
