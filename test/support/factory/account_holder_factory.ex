defmodule PaymentCompliancePlatform.Factory.AccountHolderFactory do
  @moduledoc """
  Factory for AccountHolder context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias PaymentCompliancePlatform.AccountHolderContext.AccountHolder

      def account_holder_factory do
        unique_suffix = String.slice(Ecto.UUID.generate(), 0, 8)

        %AccountHolder{
          name: "some name" <> unique_suffix,
          type: "some type" <> unique_suffix,
          tenant: build(:tenant)
        }
      end
    end
  end
end
