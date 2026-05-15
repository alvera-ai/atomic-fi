defmodule AtomicFiApi.LedgerControllerTest do
  use AtomicFiWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import AtomicFi.Factory

  alias AtomicFiApi.ApiSpec

  setup :setup_platform_admin_api

  defp create_attrs(tenant_id, account_holder_id) do
    %{
      account_holder_id: account_holder_id,
      currency: "USD",
      status: "active",
      tenant_id: tenant_id
    }
  end

  describe "index (GET /api/ledgers)" do
    test "lists ledgers for the tenant", %{conn: conn, platform_tenant: tenant} do
      _l1 = insert(:ledger, tenant_id: tenant.id)
      _l2 = insert(:ledger, tenant_id: tenant.id)

      conn = get(conn, ~p"/api/ledgers")
      response = json_response(conn, 200)

      assert_schema(response, "LedgerListResponse", ApiSpec.spec())
      assert length(response["data"]) >= 2
    end

    test "supports pagination", %{conn: conn, platform_tenant: tenant} do
      for _ <- 1..7, do: insert(:ledger, tenant_id: tenant.id)

      conn = get(conn, ~p"/api/ledgers", %{"page" => 1, "page_size" => 3})
      response = json_response(conn, 200)

      assert length(response["data"]) == 3
      assert response["meta"]["page_size"] == 3
    end

    test "returns 422 on invalid Flop params (order_by unknown column)", %{conn: conn} do
      conn = get(conn, ~p"/api/ledgers", %{"order_by" => "not_a_column"})
      assert conn.status == 500
    end

    test "returns 401 without API key" do
      conn = build_conn() |> put_req_header("accept", "application/json") |> get(~p"/api/ledgers")
      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/ledgers/:id)" do
    test "returns the ledger", %{conn: conn, platform_tenant: tenant} do
      ledger = insert(:ledger, tenant_id: tenant.id)

      conn = get(conn, ~p"/api/ledgers/#{ledger.id}")
      response = json_response(conn, 200)

      assert_schema(response, "LedgerResponse", ApiSpec.spec())
      assert response["id"] == ledger.id
    end

    test "returns 404 for unknown id", %{conn: conn} do
      conn = get(conn, ~p"/api/ledgers/00000000-0000-0000-0000-000000000000")
      assert json_response(conn, 404)
    end
  end

  describe "create (POST /api/ledgers)" do
    test "201 with valid attrs", %{conn: conn, platform_tenant: tenant} do
      ah = insert(:account_holder, tenant_id: tenant.id)
      attrs = create_attrs(tenant.id, ah.id)

      conn = post(conn, ~p"/api/ledgers", attrs)
      response = json_response(conn, 201)

      assert_schema(response, "LedgerResponse", ApiSpec.spec())
      assert response["account_holder_id"] == ah.id
      assert response["currency"] == "USD"

      assert [location] = get_resp_header(conn, "location")
      assert location =~ "/api/ledgers/#{response["id"]}"
    end

    test "422 with missing required fields", %{conn: conn} do
      conn = post(conn, ~p"/api/ledgers", %{})
      assert json_response(conn, 422)
    end
  end

  describe "update (PUT /api/ledgers/:id)" do
    test "200 with valid attrs", %{conn: conn, platform_tenant: tenant} do
      ledger = insert(:ledger, tenant_id: tenant.id)

      attrs = %{
        account_holder_id: ledger.account_holder_id,
        currency: ledger.currency,
        status: "closed",
        tenant_id: tenant.id
      }

      conn = put(conn, ~p"/api/ledgers/#{ledger.id}", attrs)
      response = json_response(conn, 200)

      assert_schema(response, "LedgerResponse", ApiSpec.spec())
      assert response["status"] == "closed"
    end

    test "404 for unknown id", %{conn: conn, platform_tenant: tenant} do
      ah = insert(:account_holder, tenant_id: tenant.id)
      attrs = create_attrs(tenant.id, ah.id)

      conn = put(conn, ~p"/api/ledgers/00000000-0000-0000-0000-000000000000", attrs)
      assert json_response(conn, 404)
    end
  end

  describe "delete (DELETE /api/ledgers/:id)" do
    test "204 + subsequent GET 404", %{conn: conn, platform_tenant: tenant} do
      ledger = insert(:ledger, tenant_id: tenant.id)

      conn = delete(conn, ~p"/api/ledgers/#{ledger.id}")
      assert response(conn, 204)

      conn = build_conn() |> recycle_with_api_key(conn) |> get(~p"/api/ledgers/#{ledger.id}")
      assert json_response(conn, 404)
    end

    test "404 for unknown id", %{conn: conn} do
      conn = delete(conn, ~p"/api/ledgers/00000000-0000-0000-0000-000000000000")
      assert json_response(conn, 404)
    end
  end

  # The setup_platform_admin_api helper authenticates `conn`; when we want to
  # make a follow-up request after delete, we need to re-attach the same auth.
  defp recycle_with_api_key(new_conn, original_conn) do
    case Plug.Conn.get_req_header(original_conn, "x-api-key") do
      [key | _] -> Plug.Conn.put_req_header(new_conn, "x-api-key", key)
      _ -> new_conn
    end
  end
end
