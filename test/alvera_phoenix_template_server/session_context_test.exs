defmodule AlveraPhoenixTemplateServer.SessionContextTest do
  use AlveraPhoenixTemplateServer.DataCase

  alias AlveraPhoenixTemplateServer.SessionContext
  alias AlveraPhoenixTemplateServer.SessionContext.Session

  import AlveraPhoenixTemplateServer.Factory

  describe "session changeset validations" do
    test "requires type, session_token, role_id, tenant_id" do
      changeset = Session.changeset(%Session{}, %{})

      assert %{
               type: ["can't be blank"],
               session_token: ["can't be blank"],
               role_id: ["can't be blank"],
               tenant_id: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates type is :user or :api" do
      attrs = %{
        type: :invalid,
        active: true,
        session_token: :crypto.strong_rand_bytes(32),
        role_id: Ecto.UUID.generate(),
        tenant_id: Ecto.UUID.generate()
      }

      changeset = Session.changeset(%Session{}, attrs)

      assert %{type: ["is invalid"]} = errors_on(changeset)
    end

    test "type :user requires user_id to be present" do
      attrs = %{
        type: :user,
        active: true,
        session_token: :crypto.strong_rand_bytes(32),
        role_id: Ecto.UUID.generate(),
        tenant_id: Ecto.UUID.generate(),
        user_id: nil,
        api_key_id: nil
      }

      changeset = Session.changeset(%Session{}, attrs)

      assert %{user_id: ["must be present when type is :user"]} = errors_on(changeset)
    end

    test "type :user requires api_key_id to be null" do
      attrs = %{
        type: :user,
        active: true,
        session_token: :crypto.strong_rand_bytes(32),
        role_id: Ecto.UUID.generate(),
        tenant_id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        api_key_id: Ecto.UUID.generate()
      }

      changeset = Session.changeset(%Session{}, attrs)

      assert %{api_key_id: ["must be null when type is :user"]} = errors_on(changeset)
    end

    test "type :api requires api_key_id to be present" do
      attrs = %{
        type: :api,
        active: true,
        session_token: :crypto.strong_rand_bytes(32),
        role_id: Ecto.UUID.generate(),
        tenant_id: Ecto.UUID.generate(),
        user_id: nil,
        api_key_id: nil
      }

      changeset = Session.changeset(%Session{}, attrs)

      assert %{api_key_id: ["must be present when type is :api"]} = errors_on(changeset)
    end

    test "type :api requires user_id to be null" do
      attrs = %{
        type: :api,
        active: true,
        session_token: :crypto.strong_rand_bytes(32),
        role_id: Ecto.UUID.generate(),
        tenant_id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        api_key_id: Ecto.UUID.generate()
      }

      changeset = Session.changeset(%Session{}, attrs)

      assert %{user_id: ["must be null when type is :api"]} = errors_on(changeset)
    end

    test "active defaults to true" do
      tenant_id = insert(:tenant).id
      user_id = insert(:user, tenant_id: tenant_id).id
      role_id = insert(:role, tenant_id: tenant_id).id

      attrs = %{
        type: :user,
        session_token: :crypto.strong_rand_bytes(32),
        user_id: user_id,
        role_id: role_id,
        tenant_id: tenant_id
      }

      changeset = Session.changeset(%Session{}, attrs)

      assert get_field(changeset, :active) == true
    end
  end

  describe "create_session/1" do
    test "creates valid user session with preloaded associations" do
      attrs = params_for(:session, type: :user)

      assert {:ok, %Session{} = session} = SessionContext.create_session(attrs)
      assert session.type == :user
      assert session.active == true
      assert session.user_id != nil
      assert session.api_key_id == nil
      assert session.role_id != nil
      assert session.tenant_id != nil

      # Verify associations are preloaded
      assert session.user != nil
      assert session.role != nil
      assert session.tenant != nil
      assert session.api_key == nil
    end

    test "creates valid api session with preloaded associations" do
      attrs = params_for(:session, type: :api)

      assert {:ok, %Session{} = session} = SessionContext.create_session(attrs)
      assert session.type == :api
      assert session.active == true
      assert session.api_key_id != nil
      assert session.user_id == nil
      assert session.role_id != nil
      assert session.tenant_id != nil

      # Verify associations are preloaded
      assert session.api_key != nil
      assert session.role != nil
      assert session.tenant != nil
      assert session.user == nil
    end

    test "returns error for invalid user session (missing user_id)" do
      attrs = params_for(:session, type: :user, user_id: nil)

      assert {:error, %Ecto.Changeset{} = changeset} = SessionContext.create_session(attrs)
      assert %{user_id: ["must be present when type is :user"]} = errors_on(changeset)
    end

    test "returns error for invalid api session (missing api_key_id)" do
      attrs = params_for(:session, type: :api, api_key_id: nil)

      assert {:error, %Ecto.Changeset{} = changeset} = SessionContext.create_session(attrs)
      assert %{api_key_id: ["must be present when type is :api"]} = errors_on(changeset)
    end

    test "enforces unique session_token constraint" do
      token = :crypto.strong_rand_bytes(32)
      attrs1 = params_for(:session, session_token: token)
      attrs2 = params_for(:session, session_token: token)

      assert {:ok, _session1} = SessionContext.create_session(attrs1)
      assert {:error, %Ecto.Changeset{} = changeset} = SessionContext.create_session(attrs2)
      assert %{session_token: ["has already been taken"]} = errors_on(changeset)
    end

    test "returns error for user session with api_key_id" do
      tenant_id = insert(:tenant).id
      user_id = insert(:user, tenant_id: tenant_id).id
      api_key_id = insert(:api_key, tenant_id: tenant_id).id
      role_id = insert(:role, tenant_id: tenant_id).id

      attrs = %{
        type: :user,
        active: true,
        session_token: :crypto.strong_rand_bytes(32),
        user_id: user_id,
        api_key_id: api_key_id,
        role_id: role_id,
        tenant_id: tenant_id
      }

      assert {:error, %Ecto.Changeset{} = changeset} = SessionContext.create_session(attrs)
      assert %{api_key_id: ["must be null when type is :user"]} = errors_on(changeset)
    end

    test "returns error for api session with user_id" do
      tenant_id = insert(:tenant).id
      user_id = insert(:user, tenant_id: tenant_id).id
      api_key_id = insert(:api_key, tenant_id: tenant_id).id
      role_id = insert(:role, tenant_id: tenant_id).id

      attrs = %{
        type: :api,
        active: true,
        session_token: :crypto.strong_rand_bytes(32),
        user_id: user_id,
        api_key_id: api_key_id,
        role_id: role_id,
        tenant_id: tenant_id
      }

      assert {:error, %Ecto.Changeset{} = changeset} = SessionContext.create_session(attrs)
      assert %{user_id: ["must be null when type is :api"]} = errors_on(changeset)
    end
  end

  describe "update_session/2" do
    test "updates session and preloads associations" do
      session = insert(:session)

      update_attrs = %{
        active: false,
        metadata: %{"logged_out" => true}
      }

      assert {:ok, %Session{} = updated_session} =
               SessionContext.update_session(session, update_attrs)

      assert updated_session.active == false
      assert updated_session.metadata == %{"logged_out" => true}

      # Verify associations are still preloaded
      assert updated_session.user != nil
      assert updated_session.role != nil
      assert updated_session.tenant != nil
    end

    test "returns error changeset for invalid updates" do
      session = insert(:session)

      # Try to set user_id to nil for user session (invalid)
      update_attrs = %{user_id: nil}

      assert {:error, %Ecto.Changeset{} = changeset} =
               SessionContext.update_session(session, update_attrs)

      assert %{user_id: ["must be present when type is :user"]} = errors_on(changeset)
    end
  end

  describe "delete_session/1" do
    test "deletes the session", %{session: system_session} do
      session = insert(:session)

      assert {:ok, %Session{}} = SessionContext.delete_session(session)

      assert_raise Ecto.NoResultsError, fn ->
        SessionContext.get_session!(system_session, session.id)
      end
    end
  end

  describe "list_sessions/2" do
    test "returns all sessions", %{session: system_session} do
      session1 = insert(:session)
      session2 = insert(:session, type: :api)

      assert {:ok, {sessions, _meta}} = SessionContext.list_sessions(system_session)

      assert length(sessions) == 2
      assert session1.id in Enum.map(sessions, & &1.id)
      assert session2.id in Enum.map(sessions, & &1.id)
    end

    test "returns empty list when no sessions exist", %{session: system_session} do
      assert {:ok, {sessions, _meta}} = SessionContext.list_sessions(system_session)
      assert sessions == []
    end
  end

  describe "get_session!/2" do
    test "returns the session with given id", %{session: system_session} do
      session = insert(:session)

      retrieved_session = SessionContext.get_session!(system_session, session.id)

      assert retrieved_session.id == session.id
    end

    test "raises when session does not exist", %{session: system_session} do
      assert_raise Ecto.NoResultsError, fn ->
        SessionContext.get_session!(system_session, Ecto.UUID.generate())
      end
    end
  end

  describe "change_session/1" do
    test "returns a session changeset" do
      session = insert(:session)

      assert %Ecto.Changeset{} = SessionContext.change_session(session)
    end

    test "returns changeset with given attrs" do
      session = insert(:session)

      changeset = SessionContext.change_session(session, %{active: false})

      assert changeset.changes.active == false
    end
  end
end
