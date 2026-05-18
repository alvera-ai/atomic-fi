defmodule AtomicFi.Factory.BeneficialOwnerFactory do
  @moduledoc """
  Factory for BeneficialOwner context schemas.

  BeneficialOwner owns no FK to LegalEntity — LE carries the FK back via
  `legal_entities.beneficial_owner_id`, with subject_type ∈
  {`:account_holder_beneficial_owner`, `:counterparty_beneficial_owner`}.
  This factory only inserts the BO; no LE is cascaded. `legal_entity` is
  initialised to `nil` so `bo.legal_entity` reads don't trip on the
  `%Ecto.Association.NotLoaded{}` sentinel before hydration. Tests that
  need the LE loaded call `with_hydrated_beneficial_owner/1` from
  `AtomicFi.Factory` after inserting the LE.
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
          legal_entity: nil,
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
