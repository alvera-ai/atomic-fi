defmodule AtomicFi.Factory.PaymentAccountFactory do
  @moduledoc """
  Factory for PaymentAccount context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.PaymentAccountContext.PaymentAccount

      def payment_account_factory(attrs \\ %{}) do
        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        account_holder_id =
          Map.get_lazy(attrs, :account_holder_id, fn ->
            insert(:account_holder, tenant_id: tenant_id).id
          end)

        %PaymentAccount{
          account_type: :bank_account,
          status: :active,
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
