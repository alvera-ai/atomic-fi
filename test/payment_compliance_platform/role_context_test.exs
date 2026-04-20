defmodule PaymentCompliancePlatform.RoleContextTest do
  use PaymentCompliancePlatform.DataCase

  alias PaymentCompliancePlatform.OpenApiSchema.RoleRequest
  alias PaymentCompliancePlatform.RoleContext

  describe "roles" do
    alias PaymentCompliancePlatform.RoleContext.Role

    import PaymentCompliancePlatform.Factory

    @invalid_attrs %RoleRequest{
      name: nil,
      description: nil,
      metadata: nil,
      tenant_id: nil,
      customer_id: nil
    }

    test "list_roles/2 returns all roles", %{session: session} do
      role = insert(:role, tenant_id: session.tenant_id)

      {:ok, {roles, _meta}} = RoleContext.list_roles(session)
      assert Enum.any?(roles, fn r -> r.id == role.id end)
    end

    test "get_role!/2 returns the role with given id", %{session: session} do
      role = insert(:role, tenant_id: session.tenant_id)

      assert RoleContext.get_role!(session, role.id).id == role.id
    end

    test "create_role/2 with valid data creates a role", %{session: session} do
      valid_attrs = %RoleRequest{
        name: "some name",
        description: "some description",
        metadata: %{},
        tenant_id: session.tenant_id,
        customer_id: nil
      }

      assert {:ok, %Role{} = role} = RoleContext.create_role(session, valid_attrs)
      assert role.name == "some name"
      assert role.description == "some description"
      assert role.metadata == %{}
    end

    test "create_role/2 with invalid data returns error changeset", %{session: session} do
      assert {:error, %Ecto.Changeset{}} = RoleContext.create_role(session, @invalid_attrs)
    end

    test "update_role/3 with valid data updates the role", %{session: session} do
      role = insert(:role, tenant_id: session.tenant_id)

      update_attrs = %RoleRequest{
        name: "some updated name",
        description: "some updated description",
        metadata: %{},
        tenant_id: session.tenant_id,
        customer_id: nil
      }

      assert {:ok, %Role{} = role} = RoleContext.update_role(session, role, update_attrs)
      assert role.name == "some updated name"
      assert role.description == "some updated description"
      assert role.metadata == %{}
    end

    test "update_role/3 with invalid data returns error changeset", %{session: session} do
      role = insert(:role, tenant_id: session.tenant_id)

      assert {:error, %Ecto.Changeset{}} =
               RoleContext.update_role(session, role, @invalid_attrs)

      assert RoleContext.get_role!(session, role.id).id == role.id
    end

    test "delete_role/2 deletes the role", %{session: session} do
      role = insert(:role, tenant_id: session.tenant_id)

      assert {:ok, %Role{}} = RoleContext.delete_role(session, role)
      assert_raise Ecto.NoResultsError, fn -> RoleContext.get_role!(session, role.id) end
    end

    test "change_role/1 returns a role changeset" do
      role = insert(:role)
      assert %Ecto.Changeset{} = RoleContext.change_role(role)
    end
  end
end
