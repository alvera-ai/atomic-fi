defmodule PaymentCompliancePlatform.Factory.LegalEntityFactory do
  @moduledoc """
  Factory for LegalEntity context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias PaymentCompliancePlatform.LegalEntityContext.LegalEntity

      def legal_entity_factory(attrs \\ %{}) do
        unique_suffix = String.slice(Ecto.UUID.generate(), 0, 8)

        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        %LegalEntity{
          legal_entity_type: :individual,
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

        %LegalEntity{
          legal_entity_type: :business,
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
