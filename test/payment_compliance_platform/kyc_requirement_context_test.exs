defmodule PaymentCompliancePlatform.KycRequirementContextTest do
  use PaymentCompliancePlatform.DataCase

  alias PaymentCompliancePlatform.KycRequirementContext
  alias PaymentCompliancePlatform.KycRequirementContext.KycRequirement
  alias PaymentCompliancePlatform.OpenApiSchema.KycRequirementRequest
  import PaymentCompliancePlatform.Factory

  describe "kyc_requirements" do
    test "list_kyc_requirements/1 returns all kyc_requirements for tenant", %{session: session} do
      insert(:kyc_requirement, tenant_id: session.tenant_id)
      {:ok, {kyc_requirements, _meta}} = KycRequirementContext.list_kyc_requirements(session)
      assert kyc_requirements != []
    end

    test "list_kyc_requirements/1 returns own tenant records", %{session: session} do
      own = insert(:kyc_requirement, tenant_id: session.tenant_id)

      {:ok, {kyc_requirements, _meta}} = KycRequirementContext.list_kyc_requirements(session)
      ids = Enum.map(kyc_requirements, & &1.id)
      assert own.id in ids
    end

    test "get_kyc_requirement!/2 returns the kyc_requirement with given id", %{session: session} do
      kyc_requirement = insert(:kyc_requirement, tenant_id: session.tenant_id)

      assert %KycRequirement{id: id} =
               KycRequirementContext.get_kyc_requirement!(session, kyc_requirement.id)

      assert id == kyc_requirement.id
    end

    test "create_kyc_requirement/2 with valid data creates a kyc_requirement", %{
      session: session
    } do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      request = %KycRequirementRequest{
        scope: :account_holder,
        requirement_type: :identity_document,
        status: :pending,
        account_holder_id: account_holder.id,
        legal_entity_id: legal_entity.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %KycRequirement{} = kyc_requirement} =
               KycRequirementContext.create_kyc_requirement(session, request)

      assert kyc_requirement.scope == :account_holder
      assert kyc_requirement.requirement_type == :identity_document
      assert kyc_requirement.status == :pending
      assert kyc_requirement.account_holder_id == account_holder.id
      assert kyc_requirement.legal_entity_id == legal_entity.id
      assert kyc_requirement.tenant_id == session.tenant_id
    end

    test "create_kyc_requirement/2 with optional fields", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      request = %KycRequirementRequest{
        scope: :beneficial_owner,
        requirement_type: :ubo_declaration,
        status: :submitted,
        deadline: ~D[2026-12-31],
        kyc_requirement_number: "KYC-001",
        account_holder_id: account_holder.id,
        legal_entity_id: legal_entity.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %KycRequirement{} = kyc_requirement} =
               KycRequirementContext.create_kyc_requirement(session, request)

      assert kyc_requirement.scope == :beneficial_owner
      assert kyc_requirement.requirement_type == :ubo_declaration
      assert kyc_requirement.status == :submitted
      assert kyc_requirement.deadline == ~D[2026-12-31]
      assert kyc_requirement.kyc_requirement_number == "KYC-001"
    end

    test "create_kyc_requirement/2 with invalid data returns error changeset", %{
      session: session
    } do
      request = %KycRequirementRequest{
        scope: nil,
        requirement_type: nil,
        account_holder_id: nil,
        legal_entity_id: nil,
        tenant_id: session.tenant_id
      }

      assert {:error, %Ecto.Changeset{}} =
               KycRequirementContext.create_kyc_requirement(session, request)
    end

    test "create_kyc_requirement/2 enforces natural key uniqueness", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      request = %KycRequirementRequest{
        scope: :account_holder,
        requirement_type: :identity_document,
        account_holder_id: account_holder.id,
        legal_entity_id: legal_entity.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, _} = KycRequirementContext.create_kyc_requirement(session, request)
      assert {:error, changeset} = KycRequirementContext.create_kyc_requirement(session, request)

      errors = errors_on(changeset)

      assert Map.get(errors, :account_holder_id) ==
               [
                 "requirement already exists for this account holder, legal entity, scope and type"
               ] or
               Map.get(errors, :legal_entity_id) ==
                 [
                   "requirement already exists for this account holder, legal entity, scope and type"
                 ]
    end

    test "create_kyc_requirement/2 allows same natural key for different scope", %{
      session: session
    } do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      req1 = %KycRequirementRequest{
        scope: :account_holder,
        requirement_type: :identity_document,
        account_holder_id: account_holder.id,
        legal_entity_id: legal_entity.id,
        tenant_id: session.tenant_id
      }

      req2 = %KycRequirementRequest{
        scope: :counterparty,
        requirement_type: :identity_document,
        account_holder_id: account_holder.id,
        legal_entity_id: legal_entity.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, _} = KycRequirementContext.create_kyc_requirement(session, req1)
      assert {:ok, _} = KycRequirementContext.create_kyc_requirement(session, req2)
    end

    test "update_kyc_requirement/3 with valid data updates the kyc_requirement", %{
      session: session
    } do
      kyc_requirement = insert(:kyc_requirement, tenant_id: session.tenant_id)

      request = %KycRequirementRequest{
        scope: kyc_requirement.scope,
        requirement_type: kyc_requirement.requirement_type,
        status: :approved,
        account_holder_id: kyc_requirement.account_holder_id,
        legal_entity_id: kyc_requirement.legal_entity_id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %KycRequirement{} = updated} =
               KycRequirementContext.update_kyc_requirement(session, kyc_requirement, request)

      assert updated.status == :approved
    end

    test "update_kyc_requirement/3 with invalid data returns error changeset", %{
      session: session
    } do
      kyc_requirement = insert(:kyc_requirement, tenant_id: session.tenant_id)

      request = %KycRequirementRequest{
        scope: nil,
        requirement_type: nil,
        account_holder_id: nil,
        legal_entity_id: nil,
        tenant_id: nil
      }

      assert {:error, %Ecto.Changeset{}} =
               KycRequirementContext.update_kyc_requirement(session, kyc_requirement, request)
    end

    test "delete_kyc_requirement/2 deletes the kyc_requirement", %{session: session} do
      kyc_requirement = insert(:kyc_requirement, tenant_id: session.tenant_id)

      assert {:ok, %KycRequirement{}} =
               KycRequirementContext.delete_kyc_requirement(session, kyc_requirement)

      assert_raise Ecto.NoResultsError, fn ->
        KycRequirementContext.get_kyc_requirement!(session, kyc_requirement.id)
      end
    end

    test "change_kyc_requirement/1 returns a kyc_requirement changeset", %{session: session} do
      kyc_requirement = insert(:kyc_requirement, tenant_id: session.tenant_id)

      assert %Ecto.Changeset{} =
               KycRequirementContext.change_kyc_requirement(kyc_requirement)
    end
  end
end
