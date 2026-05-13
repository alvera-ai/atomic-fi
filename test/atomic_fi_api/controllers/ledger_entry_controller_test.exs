defmodule AtomicFiApi.LedgerEntryControllerTest do
  use AtomicFiWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import AtomicFi.Factory

  alias AtomicFiApi.ApiSpec

  setup :setup_platform_admin_api

  defp create_attrs(tenant_id, ledger_account_id, account_holder_id) do
    %{
      ledger_account_id: ledger_account_id,
      account_holder_id: account_holder_id,
      currency: "USD",
      amount: 10_000,
      entry_type: "credit",
      status: "pending",
      tenant_id: tenant_id
    }
  end

  describe "index (GET /api/ledger-entries)" do
    test "lists ledger entries for tenant", %{conn: conn, platform_tenant: tenant} do
      insert(:ledger_entry, tenant_id: tenant.id)
      insert(:ledger_entry, tenant_id: tenant.id)

      conn = get(conn, ~p"/api/ledger-entries")
      response = json_response(conn, 200)

      assert_schema(response, "LedgerEntryListResponse", ApiSpec.spec())
      assert length(response["data"]) >= 2
    end

    test "supports pagination", %{conn: conn, platform_tenant: tenant} do
      for _ <- 1..6, do: insert(:ledger_entry, tenant_id: tenant.id)
      conn = get(conn, ~p"/api/ledger-entries", %{"page" => 1, "page_size" => 3})
      response = json_response(conn, 200)
      assert length(response["data"]) == 3
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/ledger-entries")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/ledger-entries/:id)" do
    test "returns the ledger entry", %{conn: conn, platform_tenant: tenant} do
      le = insert(:ledger_entry, tenant_id: tenant.id)

      conn = get(conn, ~p"/api/ledger-entries/#{le.id}")
      response = json_response(conn, 200)

      assert_schema(response, "LedgerEntryResponse", ApiSpec.spec())
      assert response["id"] == le.id
    end

    test "returns 404 for unknown id", %{conn: conn} do
      conn = get(conn, ~p"/api/ledger-entries/00000000-0000-0000-0000-000000000000")
      assert json_response(conn, 404)
    end
  end

  describe "create (POST /api/ledger-entries)" do
    test "201 with valid attrs", %{conn: conn, platform_tenant: tenant} do
      ah = insert(:account_holder, tenant_id: tenant.id)
      la = insert(:ledger_account, tenant_id: tenant.id, account_holder_id: ah.id)
      attrs = create_attrs(tenant.id, la.id, ah.id)

      conn = post(conn, ~p"/api/ledger-entries", attrs)
      response = json_response(conn, 201)

      assert_schema(response, "LedgerEntryResponse", ApiSpec.spec())
      assert response["ledger_account_id"] == la.id
      assert response["amount"] == 10_000

      assert [location] = get_resp_header(conn, "location")
      assert location =~ "/api/ledger-entries/#{response["id"]}"
    end

    test "422 with missing required fields", %{conn: conn} do
      conn = post(conn, ~p"/api/ledger-entries", %{})
      assert json_response(conn, 422)
    end
  end

  describe "update (PUT /api/ledger-entries/:id)" do
    test "200 with valid attrs", %{conn: conn, platform_tenant: tenant} do
      le = insert(:ledger_entry, tenant_id: tenant.id)

      attrs = %{
        ledger_account_id: le.ledger_account_id,
        account_holder_id: le.account_holder_id,
        currency: le.currency,
        amount: le.amount,
        entry_type: "credit",
        status: "posted",
        tenant_id: tenant.id
      }

      conn = put(conn, ~p"/api/ledger-entries/#{le.id}", attrs)
      response = json_response(conn, 200)
      assert response["status"] == "posted"
    end

    test "404 for unknown id", %{conn: conn, platform_tenant: tenant} do
      ah = insert(:account_holder, tenant_id: tenant.id)
      la = insert(:ledger_account, tenant_id: tenant.id, account_holder_id: ah.id)
      attrs = create_attrs(tenant.id, la.id, ah.id)

      conn = put(conn, ~p"/api/ledger-entries/00000000-0000-0000-0000-000000000000", attrs)
      assert json_response(conn, 404)
    end
  end

  describe "delete (DELETE /api/ledger-entries/:id)" do
    test "204 deletes the row", %{conn: conn, platform_tenant: tenant} do
      le = insert(:ledger_entry, tenant_id: tenant.id)
      conn = delete(conn, ~p"/api/ledger-entries/#{le.id}")
      assert response(conn, 204)
    end

    test "404 for unknown id", %{conn: conn} do
      conn = delete(conn, ~p"/api/ledger-entries/00000000-0000-0000-0000-000000000000")
      assert json_response(conn, 404)
    end
  end
end
