defmodule AtomicFi.Factory.AccountHolderFactory do
  @moduledoc """
  Factory for AccountHolder context schemas.

  AccountHolder owns no FK to LegalEntity — LE carries the FK back via
  `legal_entities.account_holder_id` (subject_type = :account_holder). So
  this factory only inserts the AH. For tests that need the paired identity
  LE, use `insert_account_holder_with_legal_entity/1` (defined in
  `AtomicFi.Factory`).
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.AccountHolderContext.AccountHolder

      def account_holder_factory(attrs \\ %{}) do
        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        %AccountHolder{
          account_holder_type: :individual,
          status: :pending,
          kyc_status: :not_started,
          risk_level: :low,
          enabled_currencies: ["USD"],
          tenant_id: tenant_id
        }
        |> merge_attributes(attrs)
        |> evaluate_lazy_attributes()
      end
    end
  end
end
