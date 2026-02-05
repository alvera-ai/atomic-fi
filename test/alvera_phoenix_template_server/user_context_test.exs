defmodule AlveraPhoenixTemplateServer.UserContextTest do
  use AlveraPhoenixTemplateServer.DataCase

  alias AlveraPhoenixTemplateServer.UserContext

  describe "users" do
    alias AlveraPhoenixTemplateServer.UserContext.User

    import AlveraPhoenixTemplateServer.Factory

    @invalid_attrs %{email: nil, hashed_password: nil, confirmed_at: nil}

    test "list_users/2 returns all users", %{session: session} do
      user = insert(:user, tenant_id: session.tenant_id)
      {:ok, {users, _meta}} = UserContext.list_users(session)
      # Includes system admin user + system bot user + test user
      assert length(users) == 3
      assert Enum.any?(users, fn u -> u.id == user.id end)
    end

    test "get_user!/2 returns the user with given id", %{session: session} do
      user = insert(:user, tenant_id: session.tenant_id)
      assert UserContext.get_user!(session, user.id).id == user.id
    end

    test "create_user/2 with valid data creates a user", %{session: session} do
      valid_attrs = %{
        email: "some@email.com",
        hashed_password: "some hashed_password",
        confirmed_at: ~U[2026-02-03 20:36:00.000000Z],
        tenant_id: session.tenant_id
      }

      assert {:ok, %User{} = user} = UserContext.create_user(session, valid_attrs)
      assert user.email == "some@email.com"
      assert user.hashed_password == "some hashed_password"
      assert user.confirmed_at == ~U[2026-02-03 20:36:00.000000Z]
    end

    test "create_user/2 with invalid data returns error changeset", %{session: session} do
      assert {:error, %Ecto.Changeset{}} = UserContext.create_user(session, @invalid_attrs)
    end

    test "update_user/3 with valid data updates the user", %{session: session} do
      user = insert(:user, tenant_id: session.tenant_id)

      update_attrs = %{
        email: "updated@email.com",
        hashed_password: "some updated hashed_password",
        confirmed_at: ~U[2026-02-04 20:36:00.000000Z]
      }

      assert {:ok, %User{} = user} = UserContext.update_user(session, user, update_attrs)
      assert user.email == "updated@email.com"
      assert user.hashed_password == "some updated hashed_password"
      assert user.confirmed_at == ~U[2026-02-04 20:36:00.000000Z]
    end

    test "update_user/3 with invalid data returns error changeset", %{session: session} do
      user = insert(:user, tenant_id: session.tenant_id)
      assert {:error, %Ecto.Changeset{}} = UserContext.update_user(session, user, @invalid_attrs)
      assert UserContext.get_user!(session, user.id).id == user.id
    end

    test "delete_user/2 deletes the user", %{session: session} do
      user = insert(:user, tenant_id: session.tenant_id)
      assert {:ok, %User{}} = UserContext.delete_user(session, user)
      assert_raise Ecto.NoResultsError, fn -> UserContext.get_user!(session, user.id) end
    end

    test "change_user/1 returns a user changeset" do
      user = insert(:user)
      assert %Ecto.Changeset{} = UserContext.change_user(user)
    end
  end
end
