defmodule AtomicFi.Factory.LedgerEntryFactory do
  @moduledoc """
  Factory for LedgerEntry context schemas.

  NOTE: This factory bypasses the context and inserts directly into the DB.
  It does NOT update the parent LedgerAccount.balance.

  For balance assertion tests, call LedgerEntryContext.create_ledger_entry/2 directly
  instead of insert(:ledger_entry) — only the context applies the atomic balance update.
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.LedgerEntryContext.LedgerEntry

      def ledger_entry_factory(attrs \\ %{}) do
        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        account_holder_id =
          Map.get_lazy(attrs, :account_holder_id, fn ->
            insert(:account_holder, tenant_id: tenant_id).id
          end)

        ledger_account_id =
          Map.get_lazy(attrs, :ledger_account_id, fn ->
            insert(:ledger_account,
              tenant_id: tenant_id,
              account_holder_id: account_holder_id
            ).id
          end)

        %LedgerEntry{
          account_holder_id: account_holder_id,
          ledger_account_id: ledger_account_id,
          currency: "USD",
          amount: 10_000,
          entry_type: :credit,
          status: :pending,
          tenant_id: tenant_id
        }
      end
    end
  end
end
