defmodule PaymentCompliancePlatform.SessionContext.SessionManagerTest do
  use PaymentCompliancePlatform.DataCase, async: true

  alias PaymentCompliancePlatform.Factory
  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.SessionContext.{Session, SessionManager}

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

    test "handles multiple conditions simultaneously", %{tenant: tenant, api_key: api_key, role: role} do
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
end
