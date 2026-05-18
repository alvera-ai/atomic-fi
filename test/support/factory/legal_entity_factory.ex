defmodule AtomicFi.Factory.LegalEntityFactory do
  @moduledoc """
  Factory for LegalEntity context schemas.

  LegalEntity carries the FK to its parent (AccountHolder / Counterparty /
  BeneficialOwner). `account_holder_id` is NOT NULL on every row — for
  AH-owned LEs it's the AH itself; for CP-owned and BO-owned LEs it's the
  host AH (AH-uniform compliance rollup). Pass an `:account_holder_id`
  override to attach to a specific AH; otherwise one is auto-inserted.

  ## Examples

      # AH-owned identity LE (auto-creates parent AH)
      le = insert(:legal_entity, tenant_id: tenant.id)

      # CP-owned LE
      cp = insert(:counterparty, account_holder_id: ah.id)
      le = insert(:legal_entity,
        tenant_id: tenant.id,
        subject_type: :counterparty,
        account_holder_id: ah.id,
        counterparty_id: cp.id
      )
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.LegalEntityContext.LegalEntity

      def legal_entity_factory(attrs \\ %{}) do
        unique_suffix = String.slice(Ecto.UUID.generate(), 0, 8)

        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        account_holder_id =
          Map.get_lazy(attrs, :account_holder_id, fn ->
            insert(:account_holder, tenant_id: tenant_id).id
          end)

        %LegalEntity{
          legal_entity_type: :individual,
          subject_type: :account_holder,
          account_holder_id: account_holder_id,
          first_name: "John #{unique_suffix}",
          last_name: "Doe #{unique_suffix}",
          preferred_name: "Johnny #{unique_suffix}",
          date_of_birth: ~D[1990-01-01],
          citizenship_country: "US",
          politically_exposed_person: false,
          doing_business_as_names: [],
          tenant_id: tenant_id
        }
        |> merge_attributes(attrs)
        |> evaluate_lazy_attributes()
      end

      def business_legal_entity_factory(attrs \\ %{}) do
        unique_suffix = String.slice(Ecto.UUID.generate(), 0, 8)

        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        account_holder_id =
          Map.get_lazy(attrs, :account_holder_id, fn ->
            insert(:account_holder, tenant_id: tenant_id, account_holder_type: :business).id
          end)

        %LegalEntity{
          legal_entity_type: :business,
          subject_type: :account_holder,
          account_holder_id: account_holder_id,
          legal_structure: :llc,
          business_name: "Acme Corp #{unique_suffix}",
          doing_business_as_names: ["Acme #{unique_suffix}"],
          date_formed: ~D[2020-01-01],
          website: "https://acme-#{unique_suffix}.example.com",
          citizenship_country: "US",
          politically_exposed_person: false,
          tenant_id: tenant_id
        }
        |> merge_attributes(attrs)
        |> evaluate_lazy_attributes()
      end
    end
  end
end
