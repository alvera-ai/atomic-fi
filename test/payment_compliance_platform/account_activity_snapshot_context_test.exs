defmodule PaymentCompliancePlatform.AccountActivitySnapshotContextTest do
  use PaymentCompliancePlatform.DataCase

  alias PaymentCompliancePlatform.AccountActivitySnapshotContext
  alias PaymentCompliancePlatform.AccountActivitySnapshotContext.AccountActivitySnapshot
  alias PaymentCompliancePlatform.OpenApiSchema.AccountActivitySnapshotRequest
  import PaymentCompliancePlatform.Factory

  defp make_request(session, attrs \\ %{}) do
    account_holder = insert(:account_holder, tenant_id: session.tenant_id)
    now = DateTime.utc_now()

    base = %AccountActivitySnapshotRequest{
      snapshot_type: :daily,
      period_start: DateTime.add(now, -86_400, :second),
      period_end: now,
      account_holder_id: account_holder.id,
      tenant_id: session.tenant_id
    }

    Map.merge(base, attrs)
  end

  describe "account activity snapshots" do
    test "list_account_activity_snapshots/1 returns all snapshots for tenant", %{
      session: session
    } do
      insert(:account_activity_snapshot, tenant_id: session.tenant_id)

      {:ok, {snapshots, _meta}} =
        AccountActivitySnapshotContext.list_account_activity_snapshots(session)

      assert snapshots != []
    end

    test "list_account_activity_snapshots/1 returns own tenant records", %{session: session} do
      own = insert(:account_activity_snapshot, tenant_id: session.tenant_id)

      {:ok, {snapshots, _meta}} =
        AccountActivitySnapshotContext.list_account_activity_snapshots(session)

      ids = Enum.map(snapshots, & &1.id)
      assert own.id in ids
    end

    test "get_account_activity_snapshot!/2 returns the snapshot with given id", %{
      session: session
    } do
      snapshot = insert(:account_activity_snapshot, tenant_id: session.tenant_id)

      assert %AccountActivitySnapshot{id: id} =
               AccountActivitySnapshotContext.get_account_activity_snapshot!(
                 session,
                 snapshot.id
               )

      assert id == snapshot.id
    end

    test "create_account_activity_snapshot/2 with minimal valid data creates a snapshot", %{
      session: session
    } do
      request = make_request(session)

      assert {:ok, %AccountActivitySnapshot{} = snapshot} =
               AccountActivitySnapshotContext.create_account_activity_snapshot(session, request)

      assert snapshot.snapshot_type == :daily
      assert snapshot.status == :pending
      assert snapshot.total_debit_count == 0
      assert snapshot.total_credit_count == 0
      assert snapshot.total_debit_amount == 0
      assert snapshot.total_credit_amount == 0
      assert snapshot.transaction_count == 0
      assert snapshot.flagged_for_review == false
      assert snapshot.account_holder_id == request.account_holder_id
      assert snapshot.tenant_id == session.tenant_id
    end

    test "create_account_activity_snapshot/2 with all snapshot types", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      now = DateTime.utc_now()

      for type <- [:intraday, :daily, :weekly, :monthly] do
        request = %AccountActivitySnapshotRequest{
          snapshot_type: type,
          period_start: DateTime.add(now, -86_400, :second),
          period_end: now,
          account_holder_id: account_holder.id,
          tenant_id: session.tenant_id
        }

        assert {:ok, %AccountActivitySnapshot{} = snapshot} =
                 AccountActivitySnapshotContext.create_account_activity_snapshot(session, request)

        assert snapshot.snapshot_type == type
      end
    end

    test "create_account_activity_snapshot/2 with optional fields", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      payment_account =
        insert(:payment_account,
          tenant_id: session.tenant_id,
          account_holder_id: account_holder.id
        )

      now = DateTime.utc_now()

      request = %AccountActivitySnapshotRequest{
        snapshot_type: :intraday,
        period_start: DateTime.add(now, -3600, :second),
        period_end: now,
        opening_balance: 100_000,
        closing_balance: 95_000,
        currency: "USD",
        total_debit_count: 3,
        total_credit_count: 1,
        total_debit_amount: 5_000,
        total_credit_amount: 0,
        transaction_count: 4,
        payment_account_id: payment_account.id,
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %AccountActivitySnapshot{} = snapshot} =
               AccountActivitySnapshotContext.create_account_activity_snapshot(session, request)

      assert snapshot.opening_balance == 100_000
      assert snapshot.closing_balance == 95_000
      assert snapshot.currency == "USD"
      assert snapshot.total_debit_count == 3
      assert snapshot.total_credit_count == 1
      assert snapshot.total_debit_amount == 5_000
      assert snapshot.transaction_count == 4
      assert snapshot.payment_account_id == payment_account.id
    end

    test "create_account_activity_snapshot/2 with AML flags", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      now = DateTime.utc_now()

      request = %AccountActivitySnapshotRequest{
        snapshot_type: :monthly,
        period_start: DateTime.add(now, -2_592_000, :second),
        period_end: now,
        flagged_for_review: true,
        review_reason: "Cash deposits exceeding $10,000 threshold (31 CFR §1010.310)",
        sar_reference: "SAR-2026-00123",
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %AccountActivitySnapshot{} = snapshot} =
               AccountActivitySnapshotContext.create_account_activity_snapshot(session, request)

      assert snapshot.flagged_for_review == true

      assert snapshot.review_reason ==
               "Cash deposits exceeding $10,000 threshold (31 CFR §1010.310)"

      assert snapshot.sar_reference == "SAR-2026-00123"
    end

    test "create_account_activity_snapshot/2 defaults status to :pending when not provided", %{
      session: session
    } do
      request = make_request(session)

      assert {:ok, %AccountActivitySnapshot{} = snapshot} =
               AccountActivitySnapshotContext.create_account_activity_snapshot(session, request)

      assert snapshot.status == :pending
    end

    test "create_account_activity_snapshot/2 with explicit status", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      now = DateTime.utc_now()

      request = %AccountActivitySnapshotRequest{
        snapshot_type: :daily,
        period_start: DateTime.add(now, -86_400, :second),
        period_end: now,
        status: :computed,
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %AccountActivitySnapshot{} = snapshot} =
               AccountActivitySnapshotContext.create_account_activity_snapshot(session, request)

      assert snapshot.status == :computed
    end

    test "create_account_activity_snapshot/2 rejects period_end before period_start", %{
      session: session
    } do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      now = DateTime.utc_now()

      request = %AccountActivitySnapshotRequest{
        snapshot_type: :daily,
        period_start: now,
        period_end: DateTime.add(now, -3600, :second),
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:error, %Ecto.Changeset{} = changeset} =
               AccountActivitySnapshotContext.create_account_activity_snapshot(session, request)

      errors = errors_on(changeset)
      assert errors[:period_end] != nil
    end

    test "create_account_activity_snapshot/2 with invalid data returns error changeset", %{
      session: session
    } do
      request = %AccountActivitySnapshotRequest{
        snapshot_type: nil,
        period_start: nil,
        period_end: nil,
        account_holder_id: nil,
        tenant_id: session.tenant_id
      }

      assert {:error, %Ecto.Changeset{}} =
               AccountActivitySnapshotContext.create_account_activity_snapshot(session, request)
    end

    test "create_account_activity_snapshot/2 enforces unique external_reference per tenant", %{
      session: session
    } do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      now = DateTime.utc_now()

      make_req = fn ->
        %AccountActivitySnapshotRequest{
          snapshot_type: :daily,
          period_start: DateTime.add(now, -86_400, :second),
          period_end: now,
          external_reference: "snap-ext-001",
          account_holder_id: account_holder.id,
          tenant_id: session.tenant_id
        }
      end

      assert {:ok, _} =
               AccountActivitySnapshotContext.create_account_activity_snapshot(
                 session,
                 make_req.()
               )

      assert {:error, changeset} =
               AccountActivitySnapshotContext.create_account_activity_snapshot(
                 session,
                 make_req.()
               )

      errors = errors_on(changeset)

      assert Map.get(errors, :external_reference) == ["has already been taken"] or
               Map.get(errors, :tenant_id) == ["has already been taken"]
    end

    test "create_account_activity_snapshot/2 allows nil external_reference for multiple snapshots",
         %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      now = DateTime.utc_now()

      make_req = fn ->
        %AccountActivitySnapshotRequest{
          snapshot_type: :daily,
          period_start: DateTime.add(now, -86_400, :second),
          period_end: now,
          account_holder_id: account_holder.id,
          tenant_id: session.tenant_id
        }
      end

      assert {:ok, _} =
               AccountActivitySnapshotContext.create_account_activity_snapshot(
                 session,
                 make_req.()
               )

      assert {:ok, _} =
               AccountActivitySnapshotContext.create_account_activity_snapshot(
                 session,
                 make_req.()
               )
    end

    test "update_account_activity_snapshot/3 with valid data updates the snapshot", %{
      session: session
    } do
      snapshot = insert(:account_activity_snapshot, tenant_id: session.tenant_id)

      request = %AccountActivitySnapshotRequest{
        snapshot_type: snapshot.snapshot_type,
        period_start: snapshot.period_start,
        period_end: snapshot.period_end,
        status: :computed,
        total_debit_count: 5,
        total_credit_count: 3,
        total_debit_amount: 50_000,
        total_credit_amount: 30_000,
        transaction_count: 8,
        account_holder_id: snapshot.account_holder_id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %AccountActivitySnapshot{} = updated} =
               AccountActivitySnapshotContext.update_account_activity_snapshot(
                 session,
                 snapshot,
                 request
               )

      assert updated.status == :computed
      assert updated.total_debit_count == 5
      assert updated.total_credit_count == 3
      assert updated.total_debit_amount == 50_000
      assert updated.transaction_count == 8
    end

    test "update_account_activity_snapshot/3 with invalid data returns error changeset", %{
      session: session
    } do
      snapshot = insert(:account_activity_snapshot, tenant_id: session.tenant_id)

      request = %AccountActivitySnapshotRequest{
        snapshot_type: nil,
        period_start: nil,
        period_end: nil,
        account_holder_id: nil,
        tenant_id: nil
      }

      assert {:error, %Ecto.Changeset{}} =
               AccountActivitySnapshotContext.update_account_activity_snapshot(
                 session,
                 snapshot,
                 request
               )
    end

    test "delete_account_activity_snapshot/2 deletes the snapshot", %{session: session} do
      snapshot = insert(:account_activity_snapshot, tenant_id: session.tenant_id)

      assert {:ok, %AccountActivitySnapshot{}} =
               AccountActivitySnapshotContext.delete_account_activity_snapshot(session, snapshot)

      assert_raise Ecto.NoResultsError, fn ->
        AccountActivitySnapshotContext.get_account_activity_snapshot!(session, snapshot.id)
      end
    end

    test "change_account_activity_snapshot/1 returns a snapshot changeset", %{session: session} do
      snapshot = insert(:account_activity_snapshot, tenant_id: session.tenant_id)

      assert %Ecto.Changeset{} =
               AccountActivitySnapshotContext.change_account_activity_snapshot(snapshot)
    end
  end
end
