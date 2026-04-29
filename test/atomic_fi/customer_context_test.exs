defmodule AtomicFi.CustomerContextTest do
  use AtomicFi.DataCase

  alias AtomicFi.CustomerContext

  describe "customers" do
    alias AtomicFi.CustomerContext.Customer

    @invalid_attrs %{name: nil, tenant_id: nil}

    test "list_customers/2 returns all customers", %{session: session} do
      customer = insert(:customer, tenant_id: session.tenant_id)
      {:ok, {customers, _meta}} = CustomerContext.list_customers(session)
      assert Enum.any?(customers, fn c -> c.id == customer.id end)
    end

    test "get_customer!/2 returns the customer with given id", %{session: session} do
      customer = insert(:customer, tenant_id: session.tenant_id)
      assert CustomerContext.get_customer!(session, customer.id).id == customer.id
    end

    test "create_customer/2 with valid data creates a customer", %{session: session} do
      valid_attrs = %{
        name: "some name",
        status: "active",
        description: "some description",
        metadata: %{},
        slug: "some-slug",
        tenant_id: session.tenant_id
      }

      assert {:ok, %Customer{} = customer} = CustomerContext.create_customer(session, valid_attrs)
      assert customer.name == "some name"
      assert customer.status == "active"
      assert customer.description == "some description"
      assert customer.metadata == %{}
      assert customer.slug == "some-slug"
    end

    test "create_customer/2 with invalid data returns error changeset", %{session: session} do
      assert {:error, %Ecto.Changeset{}} =
               CustomerContext.create_customer(session, @invalid_attrs)
    end

    test "update_customer/3 with valid data updates the customer", %{session: session} do
      customer = insert(:customer, tenant_id: session.tenant_id)

      update_attrs = %{
        name: "some updated name",
        status: "inactive",
        description: "some updated description",
        metadata: %{},
        slug: "some-updated-slug"
      }

      assert {:ok, %Customer{} = customer} =
               CustomerContext.update_customer(session, customer, update_attrs)

      assert customer.name == "some updated name"
      assert customer.status == "inactive"
      assert customer.description == "some updated description"
      assert customer.metadata == %{}
      assert customer.slug == "some-updated-slug"
    end

    test "update_customer/3 with invalid data returns error changeset", %{session: session} do
      customer = insert(:customer, tenant_id: session.tenant_id)

      assert {:error, %Ecto.Changeset{}} =
               CustomerContext.update_customer(session, customer, @invalid_attrs)

      assert CustomerContext.get_customer!(session, customer.id).id == customer.id
    end

    test "delete_customer/2 deletes the customer", %{session: session} do
      customer = insert(:customer, tenant_id: session.tenant_id)
      assert {:ok, %Customer{}} = CustomerContext.delete_customer(session, customer)

      assert_raise Ecto.NoResultsError, fn ->
        CustomerContext.get_customer!(session, customer.id)
      end
    end

    test "change_customer/1 returns a customer changeset" do
      customer = insert(:customer)
      assert %Ecto.Changeset{} = CustomerContext.change_customer(customer)
    end
  end
end
