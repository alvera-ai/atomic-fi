defmodule PaymentCompliancePlatformApi.PartyActivitySnapshotControllerTest do
  use PaymentCompliancePlatformWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import PaymentCompliancePlatform.Factory

  alias PaymentCompliancePlatformApi.ApiSpec

  setup :setup_platform_admin_api

  describe "index (GET /api/party-activity-snapshots)" do
    test "lists snapshots", %{conn: conn, platform_tenant: tenant} do
      holder = insert(:account_holder, tenant_id: tenant.id)

      snapshot =
        insert(:party_activity_snapshot, tenant_id: tenant.id, account_holder_id: holder.id)

      conn = get(conn, ~p"/api/party-activity-snapshots")
      response = json_response(conn, 200)

      assert_schema(response, "PartyActivitySnapshotListResponse", ApiSpec.spec())
      assert %{"data" => data, "meta" => meta} = response
      assert meta["total_count"] >= 1
      assert Enum.any?(data, fn s -> s["id"] == snapshot.id end)
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/party-activity-snapshots")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/party-activity-snapshots/:id)" do
    test "renders snapshot when id exists", %{conn: conn, platform_tenant: tenant} do
      holder = insert(:account_holder, tenant_id: tenant.id)

      snapshot =
        insert(:party_activity_snapshot, tenant_id: tenant.id, account_holder_id: holder.id)

      conn = get(conn, ~p"/api/party-activity-snapshots/#{snapshot.id}")
      response = json_response(conn, 200)

      assert_schema(response, "PartyActivitySnapshotResponse", ApiSpec.spec())
      assert response["id"] == snapshot.id
      assert response["account_holder_id"] == holder.id
    end

    test "renders 404 when snapshot does not exist", %{conn: conn} do
      conn = get(conn, ~p"/api/party-activity-snapshots/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "create (POST /api/party-activity-snapshots)" do
    test "creates snapshot with valid data", %{conn: conn, platform_tenant: tenant} do
      holder = insert(:account_holder, tenant_id: tenant.id)
      today = Date.utc_today()

      attrs = %{
        account_holder_id: holder.id,
        period_type: "monthly",
        period_start: Date.to_iso8601(Date.add(today, -30)),
        period_end: Date.to_iso8601(today),
        kyc_status_at_start: "approved",
        kyc_status_at_end: "approved",
        risk_level_at_start: "low",
        risk_level_at_end: "low",
        total_screenings: 4,
        screening_hits: 1,
        transaction_count: 20,
        total_debit_amount: 10_000,
        total_credit_amount: 12_000,
        high_risk_transaction_count: 2,
        sar_indicator: false,
        notes: "monthly review",
        tenant_id: tenant.id
      }

      conn = post(conn, ~p"/api/party-activity-snapshots", attrs)
      response = json_response(conn, 201)

      assert_schema(response, "PartyActivitySnapshotResponse", ApiSpec.spec())
      assert response["account_holder_id"] == holder.id
      assert response["period_type"] == "monthly"
      assert response["screening_hits"] == 1

      assert Plug.Conn.get_resp_header(conn, "location") == [
               "/api/party-activity-snapshots/#{response["id"]}"
             ]
    end

    test "renders errors when required fields missing", %{conn: conn, platform_tenant: tenant} do
      attrs = %{tenant_id: tenant.id}

      conn = post(conn, ~p"/api/party-activity-snapshots", attrs)
      assert json_response(conn, 422)
    end
  end

  describe "update (PUT /api/party-activity-snapshots/:id)" do
    test "updates snapshot with valid data", %{conn: conn, platform_tenant: tenant} do
      holder = insert(:account_holder, tenant_id: tenant.id)

      snapshot =
        insert(:party_activity_snapshot, tenant_id: tenant.id, account_holder_id: holder.id)

      attrs = %{
        account_holder_id: holder.id,
        period_type: Atom.to_string(snapshot.period_type),
        period_start: Date.to_iso8601(snapshot.period_start),
        period_end: Date.to_iso8601(snapshot.period_end),
        sar_indicator: true,
        screening_hits: 7,
        notes: "escalated",
        tenant_id: tenant.id
      }

      conn = put(conn, ~p"/api/party-activity-snapshots/#{snapshot.id}", attrs)
      response = json_response(conn, 200)

      assert_schema(response, "PartyActivitySnapshotResponse", ApiSpec.spec())
      assert response["id"] == snapshot.id
      assert response["sar_indicator"] == true
      assert response["screening_hits"] == 7
    end

    test "renders 404 when snapshot does not exist", %{conn: conn, platform_tenant: tenant} do
      holder = insert(:account_holder, tenant_id: tenant.id)
      today = Date.utc_today()

      attrs = %{
        account_holder_id: holder.id,
        period_type: "daily",
        period_start: Date.to_iso8601(today),
        period_end: Date.to_iso8601(today),
        tenant_id: tenant.id
      }

      conn = put(conn, ~p"/api/party-activity-snapshots/#{Ecto.UUID.generate()}", attrs)
      assert json_response(conn, 404)
    end
  end

  describe "delete (DELETE /api/party-activity-snapshots/:id)" do
    test "deletes snapshot", %{conn: conn, platform_tenant: tenant} do
      holder = insert(:account_holder, tenant_id: tenant.id)

      snapshot =
        insert(:party_activity_snapshot, tenant_id: tenant.id, account_holder_id: holder.id)

      conn = delete(conn, ~p"/api/party-activity-snapshots/#{snapshot.id}")
      assert response(conn, 204)
    end

    test "renders 404 when snapshot does not exist", %{conn: conn} do
      conn = delete(conn, ~p"/api/party-activity-snapshots/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes party activity snapshot endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"paths" => paths} = response
      assert paths["/api/party-activity-snapshots"]
      assert paths["/api/party-activity-snapshots"]["get"]
      assert paths["/api/party-activity-snapshots"]["post"]
      assert paths["/api/party-activity-snapshots/{id}"]
      assert paths["/api/party-activity-snapshots/{id}"]["get"]
      assert paths["/api/party-activity-snapshots/{id}"]["put"]
      assert paths["/api/party-activity-snapshots/{id}"]["delete"]
    end

    test "OpenAPI spec includes party activity snapshot schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => schemas}} = response
      assert schemas["PartyActivitySnapshotRequest"]
      assert schemas["PartyActivitySnapshotResponse"]
      assert schemas["PartyActivitySnapshotListResponse"]
    end
  end
end
