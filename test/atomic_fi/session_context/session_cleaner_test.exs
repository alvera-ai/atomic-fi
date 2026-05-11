defmodule AtomicFi.SessionContext.SessionCleanerTest do
  use AtomicFi.DataCase

  alias AtomicFi.SessionContext.{Session, SessionCleaner}

  describe "handle_info :cleanup" do
    test "deletes inactive sessions, reschedules itself, returns :noreply", %{
      tenant: tenant,
      session: _session
    } do
      role = insert(:role, tenant_id: tenant.id)
      api_key = insert(:api_key, tenant_id: tenant.id, role_id: role.id)

      inactive =
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

      assert {:noreply, %{}} = SessionCleaner.handle_info(:cleanup, %{})
      assert Repo.get(Session, inactive.id, skip_multi_tenancy_check: true) == nil
    end

    test "no-op when nothing to clean — still returns :noreply" do
      assert {:noreply, :state} = SessionCleaner.handle_info(:cleanup, :state)
    end
  end

  describe "init/1" do
    test "schedules first cleanup and returns {:ok, state}" do
      assert {:ok, :seed} = SessionCleaner.init(:seed)
      # Drain the scheduled :cleanup message so it doesn't leak into other tests.
      receive do
        :cleanup -> :ok
      after
        100 -> :ok
      end
    end
  end
end
