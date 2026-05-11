defmodule AtomicFi.RoleContext.UserRoleMappingTest do
  use AtomicFi.DataCase

  alias AtomicFi.RoleContext.UserRoleMapping

  describe "changeset/2" do
    test "is valid with user_id and role_id" do
      user = insert(:user)
      role = insert(:role, tenant_id: user.tenant_id)

      changeset = UserRoleMapping.changeset(%UserRoleMapping{}, %{user_id: user.id, role_id: role.id})
      assert changeset.valid?
    end

    test "is invalid without user_id" do
      role = insert(:role)
      changeset = UserRoleMapping.changeset(%UserRoleMapping{}, %{role_id: role.id})
      refute changeset.valid?
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "is invalid without role_id" do
      user = insert(:user)
      changeset = UserRoleMapping.changeset(%UserRoleMapping{}, %{user_id: user.id})
      refute changeset.valid?
      assert %{role_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "enforces unique (user_id, role_id) via the composite primary key" do
      user = insert(:user)
      role = insert(:role, tenant_id: user.tenant_id)

      {:ok, _} =
        %UserRoleMapping{}
        |> UserRoleMapping.changeset(%{user_id: user.id, role_id: role.id})
        |> Repo.insert(skip_multi_tenancy_check: true)

      # The changeset declares a unique_constraint on :user_roles_user_id_role_id_index
      # but the actual DB constraint is the composite-PK :user_roles_pkey, so Ecto
      # raises rather than returning {:error, changeset}.
      assert_raise Ecto.ConstraintError, ~r/user_roles_pkey/, fn ->
        %UserRoleMapping{}
        |> UserRoleMapping.changeset(%{user_id: user.id, role_id: role.id})
        |> Repo.insert(skip_multi_tenancy_check: true)
      end
    end

    test "rejects unknown role_id via foreign_key_constraint" do
      user = insert(:user)

      {:error, changeset} =
        %UserRoleMapping{}
        |> UserRoleMapping.changeset(%{user_id: user.id, role_id: Ecto.UUID.generate()})
        |> Repo.insert(skip_multi_tenancy_check: true)

      assert %{role_id: ["does not exist"]} = errors_on(changeset)
    end

    test "rejects unknown user_id via foreign_key_constraint" do
      role = insert(:role)

      {:error, changeset} =
        %UserRoleMapping{}
        |> UserRoleMapping.changeset(%{user_id: Ecto.UUID.generate(), role_id: role.id})
        |> Repo.insert(skip_multi_tenancy_check: true)

      assert %{user_id: ["does not exist"]} = errors_on(changeset)
    end
  end
end
