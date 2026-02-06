defmodule PaymentCompliancePlatform.AccountHolderContextTest do
  use PaymentCompliancePlatform.DataCase

  alias PaymentCompliancePlatform.AccountHolderContext

  describe "account_holders" do
    alias PaymentCompliancePlatform.AccountHolderContext.AccountHolder

    import PaymentCompliancePlatform.AccountHolderContextFixtures

    @invalid_attrs %{name: nil, type: nil}

    test "list_account_holders/2 returns all account_holders", %{session: session} do
      account_holder = account_holder_fixture()

      assert {:ok, {[^account_holder], _meta}} =
               AccountHolderContext.list_account_holders(session)
    end

    test "get_account_holder!/2 returns the account_holder with given id", %{session: session} do
      account_holder = account_holder_fixture()

      assert AccountHolderContext.get_account_holder!(session, account_holder.id) ==
               account_holder
    end

    test "create_account_holder/2 with valid data creates a account_holder", %{
      session: session,
      tenant: tenant
    } do
      valid_attrs = %{name: "some name", type: :individual, tenant_id: tenant.id}

      assert {:ok, %AccountHolder{} = account_holder} =
               AccountHolderContext.create_account_holder(session, valid_attrs)

      assert account_holder.name == "some name"
      assert account_holder.type == :individual
    end

    test "create_account_holder/2 with invalid data returns error changeset", %{session: session} do
      assert {:error, %Ecto.Changeset{}} =
               AccountHolderContext.create_account_holder(session, @invalid_attrs)
    end

    test "update_account_holder/3 with valid data updates the account_holder", %{
      session: session
    } do
      account_holder = account_holder_fixture()
      update_attrs = %{name: "some updated name", type: :business}

      assert {:ok, %AccountHolder{} = account_holder} =
               AccountHolderContext.update_account_holder(session, account_holder, update_attrs)

      assert account_holder.name == "some updated name"
      assert account_holder.type == :business
    end

    test "update_account_holder/3 with invalid data returns error changeset", %{
      session: session
    } do
      account_holder = account_holder_fixture()

      assert {:error, %Ecto.Changeset{}} =
               AccountHolderContext.update_account_holder(session, account_holder, @invalid_attrs)

      assert account_holder ==
               AccountHolderContext.get_account_holder!(session, account_holder.id)
    end

    test "delete_account_holder/2 deletes the account_holder", %{session: session} do
      account_holder = account_holder_fixture()

      assert {:ok, %AccountHolder{}} =
               AccountHolderContext.delete_account_holder(session, account_holder)

      assert_raise Ecto.NoResultsError, fn ->
        AccountHolderContext.get_account_holder!(session, account_holder.id)
      end
    end

    test "change_account_holder/1 returns a account_holder changeset" do
      account_holder = account_holder_fixture()
      assert %Ecto.Changeset{} = AccountHolderContext.change_account_holder(account_holder)
    end
  end
end
