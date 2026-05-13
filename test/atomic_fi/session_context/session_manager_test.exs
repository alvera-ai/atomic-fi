defmodule AtomicFi.SessionContext.SessionManagerTest do
  use AtomicFi.DataCase, async: true

  alias AtomicFi.Factory
  alias AtomicFi.Repo
  alias AtomicFi.SessionContext.{Session, SessionManager}

  describe "clear_expired_sessions/0" do
    setup do
      tenant = Factory.insert_tenant_with_cache()
      role = Factory.insert(:role, tenant_id: tenant.id)

      # Create API key
      api_key = Factory.insert(:api_key, tenant_id: tenant.id, role_id: role.id)

      %{tenant: tenant, api_key: api_key, role: role}
    end

    test "deletes inactive API sessions", %{tenant: tenant, api_key: api_key, role: role} do
      # Create an inactive API session
      inactive_session =
        Repo.insert!(
          %Session{
            id: Ecto.UUID.generate(),
            type: :api,
            active: false,
            session_token: :crypto.strong_rand_bytes(32),
            api_key_id: api_key.id,
            role_id: role.id,
            tenant_id: tenant.id,
            metadata: %{}
          },
          skip_multi_tenancy_check: true
        )

      # Create an active API session (should NOT be deleted)
      active_session =
        Repo.insert!(
          %Session{
            id: Ecto.UUID.generate(),
            type: :api,
            active: true,
            session_token: :crypto.strong_rand_bytes(32),
            api_key_id: api_key.id,
            role_id: role.id,
            tenant_id: tenant.id,
            metadata: %{}
          },
          skip_multi_tenancy_check: true
        )

      # Run cleanup
      {deleted_count, _} = SessionManager.clear_expired_sessions()

      # Verify inactive session was deleted
      assert deleted_count == 1
      refute Repo.get(Session, inactive_session.id, skip_multi_tenancy_check: true)

      # Verify active session still exists
      assert Repo.get(Session, active_session.id, skip_multi_tenancy_check: true)
    end

    test "verifies API sessions are auto-deleted when API key is deleted", %{
      tenant: tenant,
      api_key: api_key,
      role: role
    } do
      # Create session with valid API key
      session_with_deleted_key =
        Repo.insert!(
          %Session{
            id: Ecto.UUID.generate(),
            type: :api,
            active: true,
            session_token: :crypto.strong_rand_bytes(32),
            api_key_id: api_key.id,
            role_id: role.id,
            tenant_id: tenant.id,
            metadata: %{}
          },
          skip_multi_tenancy_check: true
        )

      # Delete the API key
      Repo.delete!(api_key, skip_multi_tenancy_check: true)

      # Verify session was auto-deleted by DB constraint (on_delete: :delete_all)
      refute Repo.get(Session, session_with_deleted_key.id, skip_multi_tenancy_check: true)

      # Cleanup should find no sessions to delete (already handled by DB)
      {deleted_count, _} = SessionManager.clear_expired_sessions()
      assert deleted_count == 0
    end

    test "does not delete active API sessions with valid keys", %{
      tenant: tenant,
      api_key: api_key,
      role: role
    } do
      # Create active session with valid API key
      active_session =
        Repo.insert!(
          %Session{
            id: Ecto.UUID.generate(),
            type: :api,
            active: true,
            session_token: :crypto.strong_rand_bytes(32),
            api_key_id: api_key.id,
            role_id: role.id,
            tenant_id: tenant.id,
            metadata: %{}
          },
          skip_multi_tenancy_check: true
        )

      # Run cleanup
      {deleted_count, _} = SessionManager.clear_expired_sessions()

      # Verify no sessions were deleted
      assert deleted_count == 0
      assert Repo.get(Session, active_session.id, skip_multi_tenancy_check: true)
    end

    test "does not delete non-API sessions", %{tenant: tenant, role: role} do
      # Create a user for the user session
      user = Factory.insert(:user, tenant_id: tenant.id)

      # Create a user session (should be ignored by cleanup)
      user_session =
        Repo.insert!(
          %Session{
            id: Ecto.UUID.generate(),
            type: :user,
            active: false,
            session_token: :crypto.strong_rand_bytes(32),
            user_id: user.id,
            role_id: role.id,
            tenant_id: tenant.id,
            metadata: %{}
          },
          skip_multi_tenancy_check: true
        )

      # Run cleanup
      {deleted_count, _} = SessionManager.clear_expired_sessions()

      # Verify user session was NOT deleted (cleanup only targets API sessions)
      assert deleted_count == 0
      assert Repo.get(Session, user_session.id, skip_multi_tenancy_check: true)
    end

    test "handles multiple conditions simultaneously", %{
      tenant: tenant,
      api_key: api_key,
      role: role
    } do
      # Create second API key that will be deleted
      second_api_key = Factory.insert(:api_key, tenant_id: tenant.id, role_id: role.id)

      # Create various session scenarios
      inactive_session =
        Repo.insert!(
          %Session{
            id: Ecto.UUID.generate(),
            type: :api,
            active: false,
            session_token: :crypto.strong_rand_bytes(32),
            api_key_id: api_key.id,
            role_id: role.id,
            tenant_id: tenant.id,
            metadata: %{}
          },
          skip_multi_tenancy_check: true
        )

      session_with_deleted_key =
        Repo.insert!(
          %Session{
            id: Ecto.UUID.generate(),
            type: :api,
            active: true,
            session_token: :crypto.strong_rand_bytes(32),
            api_key_id: second_api_key.id,
            role_id: role.id,
            tenant_id: tenant.id,
            metadata: %{}
          },
          skip_multi_tenancy_check: true
        )

      active_session =
        Repo.insert!(
          %Session{
            id: Ecto.UUID.generate(),
            type: :api,
            active: true,
            session_token: :crypto.strong_rand_bytes(32),
            api_key_id: api_key.id,
            role_id: role.id,
            tenant_id: tenant.id,
            metadata: %{}
          },
          skip_multi_tenancy_check: true
        )

      # Delete the second API key (this auto-deletes session_with_deleted_key via DB constraint)
      Repo.delete!(second_api_key, skip_multi_tenancy_check: true)

      # Run cleanup
      {deleted_count, _} = SessionManager.clear_expired_sessions()

      # Should only delete inactive_session (session_with_deleted_key already auto-deleted by DB)
      assert deleted_count == 1
      refute Repo.get(Session, inactive_session.id, skip_multi_tenancy_check: true)
      refute Repo.get(Session, session_with_deleted_key.id, skip_multi_tenancy_check: true)
      assert Repo.get(Session, active_session.id, skip_multi_tenancy_check: true)
    end
  end

  describe "clear_expired_sessions/0 - schema compatibility" do
    test "query does not reference non-existent ApiKey.active field" do
      # This test ensures the query doesn't break if ApiKey schema changes
      # The actual test is that the query compiles and runs without error
      assert {0, _} = SessionManager.clear_expired_sessions()
    end
  end

  describe "get_or_create_session/2 + cache" do
    setup do
      tenant = Factory.insert_tenant_with_cache()
      role = Factory.insert(:role, tenant_id: tenant.id)
      api_key = Factory.insert(:api_key, tenant_id: tenant.id, role_id: role.id)
      # Bust any cache from previous tests
      SessionManager.invalidate_cache(api_key.id)
      %{tenant: tenant, role: role, api_key: api_key}
    end

    test "first call creates a session in DB; second call returns cached", %{api_key: api_key} do
      {:ok, s1} = SessionManager.get_or_create_session(api_key)
      assert s1.api_key_id == api_key.id
      assert s1.active == true

      # Second call: cached
      {:ok, s2} = SessionManager.get_or_create_session(api_key)
      assert s2.id == s1.id
    end

    test "re-uses the existing active DB session if cache is cold", %{api_key: api_key} do
      {:ok, s1} = SessionManager.get_or_create_session(api_key)
      SessionManager.invalidate_cache(api_key.id)
      {:ok, s2} = SessionManager.get_or_create_session(api_key)
      assert s1.id == s2.id
    end

    test "passes metadata through to created session", %{api_key: api_key} do
      metadata = %{
        ip_address: "10.0.0.1",
        user_agent: "ua-test",
        cloudflare_metadata: %{"cf-ray" => "abc"}
      }

      {:ok, session} = SessionManager.get_or_create_session(api_key, metadata)
      assert session.metadata["ip_address"] == "10.0.0.1"
      assert session.metadata["user_agent"] == "ua-test"
      assert session.metadata["cf-ray"] == "abc"
    end
  end

  describe "get_session_data/2" do
    test "reads a key from session metadata" do
      session = %Session{metadata: %{"foo" => "bar"}}
      assert SessionManager.get_session_data(session, :foo) == "bar"
      assert SessionManager.get_session_data(session, "foo") == "bar"
      assert SessionManager.get_session_data(session, :missing) == nil
    end
  end

  describe "create_user_session_api_token/4 + get_session_by_user_token_id/1 + revoke_bearer_session/1" do
    alias AtomicFi.UserContext.UserToken

    setup do
      tenant = Factory.insert_tenant_with_cache()
      role = Factory.insert(:role, tenant_id: tenant.id)
      user = Factory.insert(:user, tenant_id: tenant.id)

      # Assign role to user so role-assumption validation passes
      Repo.insert!(
        %AtomicFi.RoleContext.UserRoleMapping{user_id: user.id, role_id: role.id},
        skip_multi_tenancy_check: true
      )

      %{tenant: tenant, role: role, user: user}
    end

    test "creates a Bearer session and a UserToken row", %{user: user, tenant: tenant, role: role} do
      {plaintext, session} =
        SessionManager.create_user_session_api_token(user, tenant, role,
          metadata: %{ip_address: "1.1.1.1", user_agent: "x", cloudflare_metadata: %{}}
        )

      assert is_binary(plaintext)
      assert session.type == :user
      assert session.user_token_id != nil
      assert session.role.id == role.id
      assert session.tenant.id == tenant.id
      assert session.user.id == user.id

      # UserToken row exists
      assert %UserToken{} =
               Repo.get(UserToken, session.user_token_id, skip_multi_tenancy_check: true)
    end

    test "clamps :expires_in below 60s up to 60s", %{user: user, tenant: tenant, role: role} do
      {_, session} =
        SessionManager.create_user_session_api_token(user, tenant, role, expires_in: 1)

      delta = DateTime.diff(session.expires_at, DateTime.utc_now(), :second)
      assert delta >= 59 and delta <= 61
    end

    test "clamps :expires_in above max down to max", %{user: user, tenant: tenant, role: role} do
      {_, session} =
        SessionManager.create_user_session_api_token(user, tenant, role, expires_in: 10_000_000)

      delta = DateTime.diff(session.expires_at, DateTime.utc_now(), :second)
      # @max_bearer_expires_in is 2_592_000 (30 days)
      assert delta >= 2_592_000 - 1 and delta <= 2_592_000 + 1
    end

    test "treats non-integer :expires_in as default", %{user: user, tenant: tenant, role: role} do
      {_, session} =
        SessionManager.create_user_session_api_token(user, tenant, role, expires_in: "bogus")

      delta = DateTime.diff(session.expires_at, DateTime.utc_now(), :second)
      # @default_bearer_expires_in is 86_400 (24h)
      assert delta >= 86_400 - 1 and delta <= 86_400 + 1
    end

    test "get_session_by_user_token_id/1 returns nil for non-binary input" do
      assert SessionManager.get_session_by_user_token_id(nil) == nil
      assert SessionManager.get_session_by_user_token_id(:not_a_string) == nil
    end

    test "get_session_by_user_token_id/1 fetches from DB then caches",
         %{user: user, tenant: tenant, role: role} do
      {_, session} =
        SessionManager.create_user_session_api_token(user, tenant, role)

      # First call: cache miss → DB
      assert %Session{id: id1} =
               SessionManager.get_session_by_user_token_id(session.user_token_id)

      # Second call: cache hit
      assert %Session{id: id2} =
               SessionManager.get_session_by_user_token_id(session.user_token_id)

      assert id1 == id2 and id1 == session.id
    end

    test "revoke_bearer_session/1 deactivates session, deletes user_token, invalidates cache",
         %{user: user, tenant: tenant, role: role} do
      {_, session} =
        SessionManager.create_user_session_api_token(user, tenant, role)

      # Warm cache
      assert %Session{} = SessionManager.get_session_by_user_token_id(session.user_token_id)

      :ok = SessionManager.revoke_bearer_session(session)

      # UserToken delete cascades to delete the linked Session (on_delete: :delete_all)
      assert Repo.get(UserToken, session.user_token_id, skip_multi_tenancy_check: true) == nil
      assert Repo.get(Session, session.id, skip_multi_tenancy_check: true) == nil
    end
  end

  describe "invalidate_cache/1" do
    test "is a no-op (returns :ok-shape) regardless of cache state" do
      # Cachex.del returns {:ok, integer}; this is just exercising the line.
      assert match?({:ok, _}, SessionManager.invalidate_cache(Ecto.UUID.generate()))
    end
  end

  describe "get_session_by_user_token_id/1 cache miss paths" do
    alias AtomicFi.UserContext.UserToken

    setup do
      tenant = Factory.insert_tenant_with_cache()
      role = Factory.insert(:role, tenant_id: tenant.id)
      user = Factory.insert(:user, tenant_id: tenant.id)

      Repo.insert!(
        %AtomicFi.RoleContext.UserRoleMapping{user_id: user.id, role_id: role.id},
        skip_multi_tenancy_check: true
      )

      %{tenant: tenant, role: role, user: user}
    end

    test "returns nil for an unknown user_token_id (cache miss + DB miss)" do
      assert SessionManager.get_session_by_user_token_id(Ecto.UUID.generate()) == nil
    end

    test "cache miss + DB hit caches and returns the session",
         %{user: user, tenant: tenant, role: role} do
      {_plaintext, session} =
        SessionManager.create_user_session_api_token(user, tenant, role)

      # Bust the cache that create_user_session_api_token populated
      cache_key = "user_token_session:#{session.user_token_id}"
      Cachex.del(:api_session_cache, cache_key)

      # First call: cache miss → DB → re-cache
      assert %Session{id: id1} =
               SessionManager.get_session_by_user_token_id(session.user_token_id)

      assert id1 == session.id

      # Second call: cache hit
      assert %Session{id: id2} =
               SessionManager.get_session_by_user_token_id(session.user_token_id)

      assert id2 == session.id

      # Cleanup so test doesn't leak data between tests
      Cachex.del(:api_session_cache, cache_key)
      _ = Repo.get(UserToken, session.user_token_id, skip_multi_tenancy_check: true)
    end
  end
end
