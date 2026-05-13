defmodule AtomicFi.Factory.PaymentAccountFactory do
  @moduledoc """
  Factory for PaymentAccount context schemas.

  Smart-dispatched on (account_holder_id, currency): a Ledger row must exist
  for that pair before a PaymentAccount can be created (the
  `ensure_linked_ledger_accounts` lifecycle hook materialises LedgerAccounts
  for that ledger, and raises if no ledger is found). The factory upserts
  the Ledger so tests don't have to seed it explicitly.
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.LedgerContext.Ledger
      alias AtomicFi.PaymentAccountContext.PaymentAccount
      alias AtomicFi.Repo

      def payment_account_factory(attrs \\ %{}) do
        attrs = Enum.into(attrs, %{})

        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn -> insert(:tenant).id end)

        account_holder_id =
          Map.get_lazy(attrs, :account_holder_id, fn ->
            insert(:account_holder, tenant_id: tenant_id).id
          end)

        currency = Map.get(attrs, :currency, "USD")

        # Idempotent upsert — one Ledger per (AH, currency); shared across
        # any other PA/CP factory calls in the same test that target the
        # same AH and currency.
        if currency do
          ensure_ledger(tenant_id, account_holder_id, currency)
        end

        %PaymentAccount{
          account_type: :bank_account,
          status: :active,
          currency: currency,
          account_holder_id: account_holder_id,
          tenant_id: tenant_id
        }
        |> merge_attributes(attrs)
        |> evaluate_lazy_attributes()
      end

      defp ensure_ledger(tenant_id, account_holder_id, currency) do
        import Ecto.Query

        query =
          from(l in Ledger,
            where:
              l.account_holder_id == ^account_holder_id and
                l.currency == ^currency
          )

        case Repo.one(query, skip_multi_tenancy_check: true) do
          %Ledger{} = existing ->
            existing

          nil ->
            insert(:ledger,
              tenant_id: tenant_id,
              account_holder_id: account_holder_id,
              currency: currency
            )
        end
      end
    end
  end
end
