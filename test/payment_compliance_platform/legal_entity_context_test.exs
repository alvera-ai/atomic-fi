defmodule PaymentCompliancePlatform.LegalEntityContextTest do
  use PaymentCompliancePlatform.DataCase

  alias PaymentCompliancePlatform.LegalEntityContext
  alias PaymentCompliancePlatform.LegalEntityContext.LegalEntity

  import PaymentCompliancePlatform.Factory

  describe "legal_entities" do
    @valid_attrs %{
      legal_entity_type: :individual,
      first_name: "John",
      last_name: "Doe",
      citizenship_country: "US",
      politically_exposed_person: false
    }

    @invalid_attrs %{legal_entity_type: nil}

    test "list_legal_entities/2 returns all legal_entities for tenant", %{session: session} do
      insert(:legal_entity, tenant_id: session.tenant_id)
      {:ok, {entities, _meta}} = LegalEntityContext.list_legal_entities(session)
      assert entities != []
    end

    test "get_legal_entity!/2 returns the legal_entity with given id", %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)
      assert %LegalEntity{id: id} = LegalEntityContext.get_legal_entity!(session, legal_entity.id)
      assert id == legal_entity.id
    end

    test "create_legal_entity/2 with valid data creates a legal_entity", %{session: session} do
      attrs = Map.put(@valid_attrs, :tenant_id, session.tenant_id)

      assert {:ok, %LegalEntity{} = legal_entity} =
               LegalEntityContext.create_legal_entity(session, attrs)

      assert legal_entity.legal_entity_type == :individual
      assert legal_entity.first_name == "John"
      assert legal_entity.last_name == "Doe"
      assert legal_entity.citizenship_country == "US"
      assert legal_entity.politically_exposed_person == false
      assert legal_entity.tenant_id == session.tenant_id
    end

    test "create_legal_entity/2 with invalid data returns error changeset", %{session: session} do
      attrs = Map.put(@invalid_attrs, :tenant_id, session.tenant_id)
      assert {:error, %Ecto.Changeset{}} = LegalEntityContext.create_legal_entity(session, attrs)
    end

    test "update_legal_entity/3 with valid data updates the legal_entity", %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      update_attrs = %{
        first_name: "Jane",
        last_name: "Smith",
        citizenship_country: "CA"
      }

      assert {:ok, %LegalEntity{} = updated} =
               LegalEntityContext.update_legal_entity(session, legal_entity, update_attrs)

      assert updated.first_name == "Jane"
      assert updated.last_name == "Smith"
      assert updated.citizenship_country == "CA"
    end

    test "update_legal_entity/3 with invalid data returns error changeset", %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      assert {:error, %Ecto.Changeset{}} =
               LegalEntityContext.update_legal_entity(session, legal_entity, %{
                 legal_entity_type: nil
               })
    end

    test "delete_legal_entity/2 deletes the legal_entity", %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)
      assert {:ok, %LegalEntity{}} = LegalEntityContext.delete_legal_entity(session, legal_entity)

      assert_raise Ecto.NoResultsError, fn ->
        LegalEntityContext.get_legal_entity!(session, legal_entity.id)
      end
    end

    test "change_legal_entity/1 returns a legal_entity changeset", %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)
      assert %Ecto.Changeset{} = LegalEntityContext.change_legal_entity(legal_entity)
    end
  end
end
