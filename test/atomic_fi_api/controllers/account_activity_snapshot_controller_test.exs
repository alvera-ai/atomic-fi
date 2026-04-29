defmodule AtomicFiApi.AccountActivitySnapshotControllerTest do
  use AtomicFiWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import AtomicFi.Factory

  alias AtomicFiApi.ApiSpec

  @now DateTime.utc_now()
  @period_start DateTime.add(@now, -86_400, :second) |> DateTime.to_iso8601()
  @period_end DateTime.to_iso8601(@now)

  @base_attrs %{
    snapshot_type: "daily",
    period_start: @period_start,
    period_end: @period_end
  }

  @update_attrs %{
    snapshot_type: "daily",
    status: "computed",
    period_start: @period_start,
    period_end: @period_end,
    total_debit_count: 5,
    total_credit_count: 3,
    total_debit_amount: 50_000,
    total_credit_amount: 30_000,
    transaction_count: 8
  }

  @invalid_attrs %{snapshot_type: nil, period_start: nil, period_end: nil}

  defp create_attrs(tenant_id, account_holder_id) do
    @base_attrs
    |> Map.put(:tenant_id, tenant_id)
    |> Map.put(:account_holder_id, account_holder_id)
  end

  defp update_attrs(tenant_id, account_holder_id) do
    @update_attrs
    |> Map.put(:tenant_id, tenant_id)
    |> Map.put(:account_holder_id, account_holder_id)
  end

  setup :setup_platform_admin_api

  setup %{platform_tenant: platform_tenant} do
    account_holder = insert(:account_holder, tenant_id: platform_tenant.id)
    %{account_holder: account_holder}
  end

  describe "index (GET /api/account-activity-snapshots)" do
    test "lists snapshots for tenant", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      _s1 =
        insert(:account_activity_snapshot,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id,
          snapshot_type: :daily
        )

      _s2 =
        insert(:account_activity_snapshot,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id,
          snapshot_type: :monthly
        )

      conn = get(conn, ~p"/api/account-activity-snapshots")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "AccountActivitySnapshotListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert is_list(data)
      assert length(data) >= 2
      assert meta["total_count"] >= 2
    end

    test "supports pagination", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      for _i <- 1..5 do
        insert(:account_activity_snapshot,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id
        )
      end

      conn =
        get(conn, ~p"/api/account-activity-snapshots", %{"page" => 1, "page_size" => 3})

      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "AccountActivitySnapshotListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert length(data) == 3
      assert meta["page"] == 1
      assert meta["page_size"] == 3
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/account-activity-snapshots")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/account-activity-snapshots/:id)" do
    setup [:create_snapshot]

    test "renders snapshot", %{conn: conn, snapshot: snapshot} do
      conn = get(conn, ~p"/api/account-activity-snapshots/#{snapshot.id}")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "AccountActivitySnapshotResponse", api_spec)

      assert %{
               "id" => id,
               "snapshot_type" => "daily",
               "status" => "pending"
             } = response

      assert id == snapshot.id
    end

    test "renders 404 when snapshot does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/account-activity-snapshots/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "renders 422 when id is invalid format", %{conn: conn} do
      conn = get(conn, ~p"/api/account-activity-snapshots/invalid-uuid")
      assert conn.status == 422
    end

    test "returns 401 without API key", %{snapshot: snapshot} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/account-activity-snapshots/#{snapshot.id}")

      assert json_response(conn, 401)
    end
  end

  describe "create (POST /api/account-activity-snapshots)" do
    test "creates snapshot", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      conn =
        post(
          conn,
          ~p"/api/account-activity-snapshots",
          create_attrs(platform_tenant.id, account_holder.id)
        )

      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "AccountActivitySnapshotResponse", api_spec)

      assert %{
               "id" => id,
               "snapshot_type" => "daily",
               "status" => "pending",
               "account_holder_id" => account_holder_id
             } = response

      assert is_binary(id)
      assert account_holder_id == account_holder.id

      assert Plug.Conn.get_resp_header(conn, "location") == [
               "/api/account-activity-snapshots/#{id}"
             ]
    end

    test "creates snapshot with optional fields", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      payment_account =
        insert(:payment_account,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id
        )

      attrs =
        create_attrs(platform_tenant.id, account_holder.id)
        |> Map.merge(%{
          snapshot_type: "intraday",
          opening_balance: 100_000,
          closing_balance: 95_000,
          currency: "USD",
          total_debit_count: 3,
          total_credit_count: 1,
          total_debit_amount: 5_000,
          total_credit_amount: 0,
          transaction_count: 4,
          payment_account_id: payment_account.id
        })

      conn = post(conn, ~p"/api/account-activity-snapshots", attrs)
      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "AccountActivitySnapshotResponse", api_spec)

      assert %{
               "snapshot_type" => "intraday",
               "opening_balance" => 100_000,
               "closing_balance" => 95_000,
               "currency" => "USD",
               "total_debit_count" => 3,
               "total_debit_amount" => 5_000,
               "transaction_count" => 4,
               "payment_account_id" => payment_account_id
             } = response

      assert payment_account_id == payment_account.id
    end

    test "creates snapshot with AML flags", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      attrs =
        create_attrs(platform_tenant.id, account_holder.id)
        |> Map.merge(%{
          snapshot_type: "monthly",
          flagged_for_review: true,
          review_reason: "Cash deposits exceeding $10,000 threshold",
          sar_reference: "SAR-2026-00123"
        })

      conn = post(conn, ~p"/api/account-activity-snapshots", attrs)
      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "AccountActivitySnapshotResponse", api_spec)

      assert %{
               "flagged_for_review" => true,
               "review_reason" => "Cash deposits exceeding $10,000 threshold",
               "sar_reference" => "SAR-2026-00123"
             } = response
    end

    test "renders errors when required fields are missing", %{conn: conn} do
      conn = post(conn, ~p"/api/account-activity-snapshots", @invalid_attrs)
      response = json_response(conn, 422)
      assert %{"errors" => errors} = response
      assert is_list(errors)
      assert errors != []
    end

    test "renders errors when snapshot_type is invalid enum", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      attrs =
        create_attrs(platform_tenant.id, account_holder.id)
        |> Map.put(:snapshot_type, "invalid_type")

      conn = post(conn, ~p"/api/account-activity-snapshots", attrs)
      assert json_response(conn, 422)
    end

    test "returns 401 without API key", %{account_holder: account_holder} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/account-activity-snapshots",
          @base_attrs |> Map.put(:account_holder_id, account_holder.id)
        )

      assert json_response(conn, 401)
    end
  end

  describe "update (PUT /api/account-activity-snapshots/:id)" do
    setup [:create_snapshot]

    test "updates snapshot with valid data", %{
      conn: conn,
      snapshot: snapshot,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      conn =
        put(
          conn,
          ~p"/api/account-activity-snapshots/#{snapshot.id}",
          update_attrs(platform_tenant.id, account_holder.id)
        )

      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "AccountActivitySnapshotResponse", api_spec)

      assert %{
               "id" => id,
               "status" => "computed",
               "total_debit_count" => 5,
               "transaction_count" => 8
             } = response

      assert id == snapshot.id
    end

    test "renders errors when data is invalid", %{conn: conn, snapshot: snapshot} do
      conn = put(conn, ~p"/api/account-activity-snapshots/#{snapshot.id}", @invalid_attrs)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert is_list(errors)
      assert errors != []
    end

    test "renders 404 when snapshot does not exist", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      non_existent_id = Ecto.UUID.generate()

      conn =
        put(
          conn,
          ~p"/api/account-activity-snapshots/#{non_existent_id}",
          update_attrs(platform_tenant.id, account_holder.id)
        )

      assert json_response(conn, 404)
    end

    test "returns 401 without API key", %{
      snapshot: snapshot,
      account_holder: account_holder
    } do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put(
          ~p"/api/account-activity-snapshots/#{snapshot.id}",
          @update_attrs |> Map.put(:account_holder_id, account_holder.id)
        )

      assert json_response(conn, 401)
    end
  end

  describe "delete (DELETE /api/account-activity-snapshots/:id)" do
    setup [:create_snapshot]

    test "deletes snapshot", %{
      conn: conn,
      snapshot: snapshot,
      plain_api_key: plain_api_key
    } do
      delete_conn = delete(conn, ~p"/api/account-activity-snapshots/#{snapshot.id}")
      assert response(delete_conn, 204)

      get_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> get(~p"/api/account-activity-snapshots/#{snapshot.id}")

      assert json_response(get_conn, 404)
    end

    test "renders 404 when snapshot does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = delete(conn, ~p"/api/account-activity-snapshots/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "cannot delete snapshot twice", %{
      conn: conn,
      snapshot: snapshot,
      plain_api_key: plain_api_key
    } do
      conn = delete(conn, ~p"/api/account-activity-snapshots/#{snapshot.id}")
      assert response(conn, 204)

      conn2 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> delete(~p"/api/account-activity-snapshots/#{snapshot.id}")

      assert json_response(conn2, 404)
    end

    test "returns 401 without API key", %{snapshot: snapshot} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> delete(~p"/api/account-activity-snapshots/#{snapshot.id}")

      assert json_response(conn, 401)
    end
  end

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes account activity snapshot endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"openapi" => "3.1.0", "paths" => paths} = response

      assert paths["/api/account-activity-snapshots"]
      assert paths["/api/account-activity-snapshots"]["get"]
      assert paths["/api/account-activity-snapshots"]["post"]
      assert paths["/api/account-activity-snapshots/{id}"]
      assert paths["/api/account-activity-snapshots/{id}"]["get"]
      assert paths["/api/account-activity-snapshots/{id}"]["put"]
      assert paths["/api/account-activity-snapshots/{id}"]["delete"]
    end

    test "OpenAPI spec includes AccountActivitySnapshot schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => schemas}} = response

      assert schemas["AccountActivitySnapshotRequest"]
      assert schemas["AccountActivitySnapshotResponse"]
      assert schemas["AccountActivitySnapshotListResponse"]
    end

    test "AccountActivitySnapshotRequest excludes server-generated readOnly fields", %{
      conn: conn
    } do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{
                 "schemas" => %{"AccountActivitySnapshotRequest" => request_schema}
               }
             } = response

      refute get_in(request_schema, ["properties", "id"])
      refute get_in(request_schema, ["properties", "inserted_at"])
      refute get_in(request_schema, ["properties", "updated_at"])

      assert get_in(request_schema, ["properties", "snapshot_type"])
      assert get_in(request_schema, ["properties", "period_start"])
      assert get_in(request_schema, ["properties", "period_end"])
      assert get_in(request_schema, ["properties", "account_holder_id"])
    end

    test "AccountActivitySnapshotResponse includes all fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{
                 "schemas" => %{"AccountActivitySnapshotResponse" => response_schema}
               }
             } = response

      assert get_in(response_schema, ["properties", "id"])
      assert get_in(response_schema, ["properties", "snapshot_type"])
      assert get_in(response_schema, ["properties", "status"])
      assert get_in(response_schema, ["properties", "period_start"])
      assert get_in(response_schema, ["properties", "period_end"])
      assert get_in(response_schema, ["properties", "account_holder_id"])
      assert get_in(response_schema, ["properties", "flagged_for_review"])
      assert get_in(response_schema, ["properties", "inserted_at"])
      assert get_in(response_schema, ["properties", "updated_at"])
    end
  end

  defp create_snapshot(%{platform_tenant: platform_tenant, account_holder: account_holder}) do
    snapshot =
      insert(:account_activity_snapshot,
        tenant_id: platform_tenant.id,
        account_holder_id: account_holder.id,
        snapshot_type: :daily,
        status: :pending
      )

    %{snapshot: snapshot}
  end
end
