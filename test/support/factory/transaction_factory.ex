defmodule AtomicFi.Factory.TransactionFactory do
  @moduledoc """
  Factory for Transaction context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.TransactionContext.Transaction

      def transaction_factory(attrs \\ %{}) do
        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        account_holder_id =
          Map.get_lazy(attrs, :account_holder_id, fn ->
            insert(:account_holder, tenant_id: tenant_id).id
          end)

        %Transaction{
          transaction_type: :credit_transfer,
          status: :pending,
          amount: 10_000,
          currency: "USD",
          account_holder_id: account_holder_id,
          tenant_id: tenant_id
        }
        |> merge_attributes(attrs)
        |> evaluate_lazy_attributes()
      end
    end
  end
end
