defmodule PaymentCompliancePlatform.BeneficialOwnerContextTest do
  use PaymentCompliancePlatform.DataCase

  alias PaymentCompliancePlatform.BeneficialOwnerContext
  alias PaymentCompliancePlatform.BeneficialOwnerContext.BeneficialOwner
  import PaymentCompliancePlatform.Factory

  describe "beneficial_owners" do
    @invalid_attrs %{control_type: nil}

    test "list_beneficial_owners/1 returns all beneficial_owners for tenant", %{session: session} do
      insert(:beneficial_owner, tenant_id: session.tenant_id)
      {:ok, {beneficial_owners, _meta}} = BeneficialOwnerContext.list_beneficial_owners(session)
      assert beneficial_owners != []
    end

    test "get_beneficial_owner!/2 returns the beneficial_owner with given id", %{
      session: session
    } do
      beneficial_owner = insert(:beneficial_owner, tenant_id: session.tenant_id)

      assert %BeneficialOwner{id: id} =
               BeneficialOwnerContext.get_beneficial_owner!(session, beneficial_owner.id)

      assert id == beneficial_owner.id
    end

    test "create_beneficial_owner/2 with valid data creates a beneficial_owner", %{
      session: session
    } do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      valid_attrs = %{
        account_holder_id: account_holder.id,
        legal_entity_id: legal_entity.id,
        control_type: :shareholder,
        ownership_pct: 30.0,
        tenant_id: session.tenant_id
      }

      assert {:ok, %BeneficialOwner{} = beneficial_owner} =
               BeneficialOwnerContext.create_beneficial_owner(session, valid_attrs)

      assert beneficial_owner.account_holder_id == account_holder.id
      assert beneficial_owner.legal_entity_id == legal_entity.id
      assert beneficial_owner.control_type == :shareholder
      assert beneficial_owner.ownership_pct == 30.0
      assert beneficial_owner.verification_status == :pending
      assert beneficial_owner.tenant_id == session.tenant_id
    end

    test "create_beneficial_owner/2 with invalid data returns error changeset", %{
      session: session
    } do
      assert {:error, %Ecto.Changeset{}} =
               BeneficialOwnerContext.create_beneficial_owner(session, @invalid_attrs)
    end

    test "update_beneficial_owner/3 with valid data updates the beneficial_owner", %{
      session: session
    } do
      beneficial_owner = insert(:beneficial_owner, tenant_id: session.tenant_id)
      update_attrs = %{verification_status: :verified, ownership_pct: 51.0}

      assert {:ok, %BeneficialOwner{} = updated} =
               BeneficialOwnerContext.update_beneficial_owner(
                 session,
                 beneficial_owner,
                 update_attrs
               )

      assert updated.verification_status == :verified
      assert updated.ownership_pct == 51.0
    end

    test "update_beneficial_owner/3 with invalid data returns error changeset", %{
      session: session
    } do
      beneficial_owner = insert(:beneficial_owner, tenant_id: session.tenant_id)

      assert {:error, %Ecto.Changeset{}} =
               BeneficialOwnerContext.update_beneficial_owner(session, beneficial_owner, %{
                 control_type: nil
               })
    end

    test "delete_beneficial_owner/2 deletes the beneficial_owner", %{session: session} do
      beneficial_owner = insert(:beneficial_owner, tenant_id: session.tenant_id)

      assert {:ok, %BeneficialOwner{}} =
               BeneficialOwnerContext.delete_beneficial_owner(session, beneficial_owner)

      assert_raise Ecto.NoResultsError, fn ->
        BeneficialOwnerContext.get_beneficial_owner!(session, beneficial_owner.id)
      end
    end

    test "change_beneficial_owner/1 returns a beneficial_owner changeset", %{session: session} do
      beneficial_owner = insert(:beneficial_owner, tenant_id: session.tenant_id)

      assert %Ecto.Changeset{} =
               BeneficialOwnerContext.change_beneficial_owner(beneficial_owner)
    end
  end
end
