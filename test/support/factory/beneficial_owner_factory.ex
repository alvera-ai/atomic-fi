defmodule AtomicFi.Factory.BeneficialOwnerFactory do
  @moduledoc """
  Factory for BeneficialOwner context schemas.

  BeneficialOwner owns no FK to LegalEntity — LE carries the FK back via
  `legal_entities.beneficial_owner_id` (subject_type = :beneficial_owner).
  This factory only inserts the BO; tests that need the paired LE use
  `insert_beneficial_owner_with_legal_entity/1` (in `AtomicFi.Factory`).
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.BeneficialOwnerContext.BeneficialOwner

      def beneficial_owner_factory(attrs \\ %{}) do
        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        account_holder_id =
          Map.get_lazy(attrs, :account_holder_id, fn ->
            insert(:account_holder, tenant_id: tenant_id).id
          end)

        %BeneficialOwner{
          account_holder_id: account_holder_id,
          ownership_pct: 25.0,
          control_type: :shareholder,
          verification_status: :pending,
          tenant_id: tenant_id
        }
        |> merge_attributes(attrs)
        |> evaluate_lazy_attributes()
      end
    end
  end
end
