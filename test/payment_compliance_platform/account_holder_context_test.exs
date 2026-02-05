defmodule PaymentCompliancePlatform.AccountHolderContextTest do
  use PaymentCompliancePlatform.DataCase

  alias PaymentCompliancePlatform.AccountHolderContext

  describe "account_holders" do
    alias PaymentCompliancePlatform.AccountHolderContext.AccountHolder

    import PaymentCompliancePlatform.AccountHolderContextFixtures

    @invalid_attrs %{name: nil, type: nil}

    test "list_account_holders/0 returns all account_holders" do
      account_holder = account_holder_fixture()
      assert AccountHolderContext.list_account_holders() == [account_holder]
    end

    test "get_account_holder!/1 returns the account_holder with given id" do
      account_holder = account_holder_fixture()
      assert AccountHolderContext.get_account_holder!(account_holder.id) == account_holder
    end

    test "create_account_holder/1 with valid data creates a account_holder" do
      valid_attrs = %{name: "some name", type: "some type"}

      assert {:ok, %AccountHolder{} = account_holder} =
               AccountHolderContext.create_account_holder(valid_attrs)

      assert account_holder.name == "some name"
      assert account_holder.type == "some type"
    end

    test "create_account_holder/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               AccountHolderContext.create_account_holder(@invalid_attrs)
    end

    test "update_account_holder/2 with valid data updates the account_holder" do
      account_holder = account_holder_fixture()
      update_attrs = %{name: "some updated name", type: "some updated type"}

      assert {:ok, %AccountHolder{} = account_holder} =
               AccountHolderContext.update_account_holder(account_holder, update_attrs)

      assert account_holder.name == "some updated name"
      assert account_holder.type == "some updated type"
    end

    test "update_account_holder/2 with invalid data returns error changeset" do
      account_holder = account_holder_fixture()

      assert {:error, %Ecto.Changeset{}} =
               AccountHolderContext.update_account_holder(account_holder, @invalid_attrs)

      assert account_holder == AccountHolderContext.get_account_holder!(account_holder.id)
    end

    test "delete_account_holder/1 deletes the account_holder" do
      account_holder = account_holder_fixture()
      assert {:ok, %AccountHolder{}} = AccountHolderContext.delete_account_holder(account_holder)

      assert_raise Ecto.NoResultsError, fn ->
        AccountHolderContext.get_account_holder!(account_holder.id)
      end
    end

    test "change_account_holder/1 returns a account_holder changeset" do
      account_holder = account_holder_fixture()
      assert %Ecto.Changeset{} = AccountHolderContext.change_account_holder(account_holder)
    end
  end
end
