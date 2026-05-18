defmodule AtomicFi.PartyActivitySnapshotContextTest do
  use AtomicFi.DataCase

  alias AtomicFi.OpenApiSchema.PartyActivitySnapshotRequest
  alias AtomicFi.PartyActivitySnapshotContext
  alias AtomicFi.PartyActivitySnapshotContext.PartyActivitySnapshot

  describe "party_activity_snapshots" do
    setup %{tenant: tenant} do
      account_holder = insert(:account_holder, tenant_id: tenant.id)
      %{account_holder: account_holder}
    end

    defp valid_request(account_holder, tenant, overrides \\ %{}) do
      today = Date.utc_today()

      base = %PartyActivitySnapshotRequest{
        account_holder_id: account_holder.id,
        period_type: :monthly,
        period_start: Date.add(today, -30),
        period_end: today,
        kyc_status_at_start: :approved,
        kyc_status_at_end: :approved,
        risk_level_at_start: :low,
        risk_level_at_end: :low,
        total_screenings: 5,
        screening_hits: 0,
        transaction_count: 12,
        total_debit_amount: 5_000,
        total_credit_amount: 8_000,
        high_risk_transaction_count: 0,
        sar_indicator: false,
        notes: "routine monthly review",
        tenant_id: tenant.id
      }

      struct!(base, overrides)
    end

    test "list_party_activity_snapshots/2 returns snapshots for the tenant", %{
      session: session,
      account_holder: holder,
      tenant: tenant
    } do
      snapshot =
        insert(:party_activity_snapshot, tenant_id: tenant.id, account_holder_id: holder.id)

      {:ok, {[result], _meta}} =
        PartyActivitySnapshotContext.list_party_activity_snapshots(session)

      assert result.id == snapshot.id
    end

    test "get_party_activity_snapshot!/2 returns snapshot by id", %{
      session: session,
      account_holder: holder,
      tenant: tenant
    } do
      snapshot =
        insert(:party_activity_snapshot, tenant_id: tenant.id, account_holder_id: holder.id)

      result = PartyActivitySnapshotContext.get_party_activity_snapshot!(session, snapshot.id)
      assert result.id == snapshot.id
    end

    test "create_party_activity_snapshot/2 with valid data creates a snapshot", %{
      session: session,
      account_holder: holder,
      tenant: tenant
    } do
      request = valid_request(holder, tenant)

      assert {:ok, %PartyActivitySnapshot{} = snapshot} =
               PartyActivitySnapshotContext.create_party_activity_snapshot(session, request)

      assert snapshot.account_holder_id == holder.id
      assert snapshot.period_type == :monthly
      assert snapshot.total_screenings == 5
      assert snapshot.sar_indicator == false
    end

    test "create_party_activity_snapshot/2 mirrors AH :prohibited risk_level (scenario #10)", %{
      session: session,
      account_holder: holder,
      tenant: tenant
    } do
      request =
        valid_request(holder, tenant, %{
          risk_level_at_start: :high,
          risk_level_at_end: :prohibited
        })

      assert {:ok,
              %PartyActivitySnapshot{
                risk_level_at_start: :high,
                risk_level_at_end: :prohibited
              }} =
               PartyActivitySnapshotContext.create_party_activity_snapshot(session, request)
    end

    test "create_party_activity_snapshot/2 rejects period_end before period_start", %{
      session: session,
      account_holder: holder,
      tenant: tenant
    } do
      today = Date.utc_today()

      request =
        valid_request(holder, tenant, %{
          period_start: today,
          period_end: Date.add(today, -1)
        })

      assert {:error, changeset} =
               PartyActivitySnapshotContext.create_party_activity_snapshot(session, request)

      assert errors_on(changeset)[:period_end]
    end

    test "create_party_activity_snapshot/2 rejects duplicate (holder, period_type, period_start, tenant)",
         %{session: session, account_holder: holder, tenant: tenant} do
      request = valid_request(holder, tenant)

      {:ok, _first} =
        PartyActivitySnapshotContext.create_party_activity_snapshot(session, request)

      assert {:error, changeset} =
               PartyActivitySnapshotContext.create_party_activity_snapshot(session, request)

      errors = errors_on(changeset)

      assert Map.get(errors, :account_holder_id) ||
               Map.get(errors, :period_type) ||
               Map.get(errors, :period_start) ||
               Map.get(errors, :tenant_id)
    end

    test "update_party_activity_snapshot/3 with valid data updates the snapshot", %{
      session: session,
      account_holder: holder,
      tenant: tenant
    } do
      snapshot =
        insert(:party_activity_snapshot, tenant_id: tenant.id, account_holder_id: holder.id)

      request =
        valid_request(holder, tenant, %{
          period_type: snapshot.period_type,
          period_start: snapshot.period_start,
          period_end: snapshot.period_end,
          sar_indicator: true,
          screening_hits: 3,
          notes: "escalated for review"
        })

      assert {:ok, updated} =
               PartyActivitySnapshotContext.update_party_activity_snapshot(
                 session,
                 snapshot,
                 request
               )

      assert updated.sar_indicator == true
      assert updated.screening_hits == 3
      assert updated.notes == "escalated for review"
    end

    test "delete_party_activity_snapshot/2 deletes the snapshot", %{
      session: session,
      account_holder: holder,
      tenant: tenant
    } do
      snapshot =
        insert(:party_activity_snapshot, tenant_id: tenant.id, account_holder_id: holder.id)

      assert {:ok, %PartyActivitySnapshot{}} =
               PartyActivitySnapshotContext.delete_party_activity_snapshot(session, snapshot)

      assert_raise Ecto.NoResultsError, fn ->
        PartyActivitySnapshotContext.get_party_activity_snapshot!(session, snapshot.id)
      end
    end

    test "change_party_activity_snapshot/2 returns a changeset", %{
      account_holder: holder,
      tenant: tenant
    } do
      snapshot =
        insert(:party_activity_snapshot, tenant_id: tenant.id, account_holder_id: holder.id)

      assert %Ecto.Changeset{} =
               PartyActivitySnapshotContext.change_party_activity_snapshot(snapshot)
    end
  end
end
