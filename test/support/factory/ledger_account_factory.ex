defmodule AtomicFi.Factory.LedgerAccountFactory do
  @moduledoc """
  Factory for LedgerAccount context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.LedgerAccountContext.LedgerAccount

      def ledger_account_factory(attrs \\ %{}) do
        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        account_holder_id =
          Map.get_lazy(attrs, :account_holder_id, fn ->
            insert(:account_holder, tenant_id: tenant_id).id
          end)

        ledger_id =
          Map.get_lazy(attrs, :ledger_id, fn ->
            insert(:ledger,
              tenant_id: tenant_id,
              account_holder_id: account_holder_id
            ).id
          end)

        %LedgerAccount{
          account_holder_id: account_holder_id,
          ledger_id: ledger_id,
          currency: "USD",
          account_type: :asset,
          status: :active,
          balance: 0,
          tenant_id: tenant_id
        }
      end
    end
  end
end
