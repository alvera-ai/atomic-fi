defmodule AtomicFi.Factory.LedgerFactory do
  @moduledoc """
  Factory for Ledger context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.LedgerContext.Ledger

      def ledger_factory(attrs \\ %{}) do
        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        account_holder_id =
          Map.get_lazy(attrs, :account_holder_id, fn ->
            insert(:account_holder, tenant_id: tenant_id).id
          end)

        %Ledger{
          account_holder_id: account_holder_id,
          currency: "USD",
          status: :active,
          tenant_id: tenant_id
        }
      end
    end
  end
end
