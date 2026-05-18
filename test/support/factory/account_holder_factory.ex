defmodule AtomicFi.Factory.AccountHolderFactory do
  @moduledoc """
  Factory for AccountHolder context schemas.

  AccountHolder owns no FK to LegalEntity — LE carries the FK back via
  `legal_entities.account_holder_id` (subject_type = :account_holder). So
  this factory only inserts the AH; no LE is cascaded.

  `legal_entity` and `beneficial_owners` are explicitly initialised to
  `nil` / `[]` so test code can read those fields safely before hydration —
  the default `%Ecto.Association.NotLoaded{}` sentinel would trip
  `ah.legal_entity.id` reads. Tests that need the assocs loaded call
  `with_hydrated_account_holder/1` from `AtomicFi.Factory` after inserting
  the LE / BOs.
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
          legal_entity: nil,
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
