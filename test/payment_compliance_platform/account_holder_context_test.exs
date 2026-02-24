defmodule PaymentCompliancePlatform.AccountHolderContextTest do
  use PaymentCompliancePlatform.DataCase

  alias PaymentCompliancePlatform.AccountHolderContext
  alias PaymentCompliancePlatform.AccountHolderContext.AccountHolder
  import PaymentCompliancePlatform.Factory

  describe "account_holders" do
    @invalid_attrs %{holder_type: nil}

    test "list_account_holders/1 returns all account_holders for tenant", %{session: session} do
      insert(:account_holder, tenant_id: session.tenant_id)
      {:ok, {account_holders, _meta}} = AccountHolderContext.list_account_holders(session)
      assert account_holders != []
    end

    test "get_account_holder!/2 returns the account_holder with given id", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      assert %AccountHolder{id: id} =
               AccountHolderContext.get_account_holder!(session, account_holder.id)

      assert id == account_holder.id
    end

    test "create_account_holder/2 with valid data creates an account_holder", %{
      session: session
    } do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      valid_attrs = %{
        legal_entity_id: legal_entity.id,
        holder_type: :individual,
        tenant_id: session.tenant_id
      }

      assert {:ok, %AccountHolder{} = account_holder} =
               AccountHolderContext.create_account_holder(session, valid_attrs)

      assert account_holder.legal_entity_id == legal_entity.id
      assert account_holder.holder_type == :individual
      assert account_holder.status == :pending
      assert account_holder.kyc_status == :not_started
      assert account_holder.risk_level == :low
      assert account_holder.tenant_id == session.tenant_id
    end

    test "create_account_holder/2 with invalid data returns error changeset", %{session: session} do
      assert {:error, %Ecto.Changeset{}} =
               AccountHolderContext.create_account_holder(session, @invalid_attrs)
    end

    test "update_account_holder/3 with valid data updates the account_holder", %{
      session: session
    } do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      update_attrs = %{status: :active, kyc_status: :approved, risk_level: :medium}

      assert {:ok, %AccountHolder{} = updated} =
               AccountHolderContext.update_account_holder(session, account_holder, update_attrs)

      assert updated.status == :active
      assert updated.kyc_status == :approved
      assert updated.risk_level == :medium
    end

    test "update_account_holder/3 with invalid data returns error changeset", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      assert {:error, %Ecto.Changeset{}} =
               AccountHolderContext.update_account_holder(session, account_holder, %{
                 holder_type: nil
               })
    end

    test "delete_account_holder/2 deletes the account_holder", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      assert {:ok, %AccountHolder{}} =
               AccountHolderContext.delete_account_holder(session, account_holder)

      assert_raise Ecto.NoResultsError, fn ->
        AccountHolderContext.get_account_holder!(session, account_holder.id)
      end
    end

    test "change_account_holder/1 returns an account_holder changeset", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      assert %Ecto.Changeset{} = AccountHolderContext.change_account_holder(account_holder)
    end
  end
end
