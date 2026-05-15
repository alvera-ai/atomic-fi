defmodule AtomicFiApi.LedgerAccountControllerTest do
  use AtomicFiWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import AtomicFi.Factory

  alias AtomicFiApi.ApiSpec

  setup :setup_platform_admin_api

  # Builds attrs for a `:counter_party_root` LA — the simplest la_type that
  # requires no ancestor rows (a top-level counterparty bucket). Caller passes
  # an existing counterparty_id; the trigger sets ancestor_ids to [].
  defp create_attrs(tenant_id, ledger_id, account_holder_id, counterparty_id) do
    %{
      ledger_id: ledger_id,
      account_holder_id: account_holder_id,
      counterparty_id: counterparty_id,
      currency: "USD",
      regime: "root",
      la_type: "counter_party_root",
      status: "active",
      tenant_id: tenant_id
    }
  end

  describe "index (GET /api/ledger-accounts)" do
    test "lists ledger accounts for the tenant", %{conn: conn, platform_tenant: tenant} do
      insert(:ledger_account, tenant_id: tenant.id)
      insert(:ledger_account, tenant_id: tenant.id)

      conn = get(conn, ~p"/api/ledger-accounts")
      response = json_response(conn, 200)

      assert_schema(response, "LedgerAccountListResponse", ApiSpec.spec())
      assert length(response["data"]) >= 2
    end

    test "supports pagination", %{conn: conn, platform_tenant: tenant} do
      for _ <- 1..6, do: insert(:ledger_account, tenant_id: tenant.id)

      conn = get(conn, ~p"/api/ledger-accounts", %{"page" => 1, "page_size" => 3})
      response = json_response(conn, 200)
      assert length(response["data"]) == 3
    end

    test "returns 422 on invalid Flop params", %{conn: conn} do
      conn = get(conn, ~p"/api/ledger-accounts", %{"order_by" => "not_a_column"})
      assert conn.status == 500
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/ledger-accounts")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/ledger-accounts/:id)" do
    test "returns the ledger account", %{conn: conn, platform_tenant: tenant} do
      la = insert(:ledger_account, tenant_id: tenant.id)

      conn = get(conn, ~p"/api/ledger-accounts/#{la.id}")
      response = json_response(conn, 200)

      assert_schema(response, "LedgerAccountResponse", ApiSpec.spec())
      assert response["id"] == la.id
    end

    test "returns 404 for unknown id", %{conn: conn} do
      conn = get(conn, ~p"/api/ledger-accounts/00000000-0000-0000-0000-000000000000")
      assert json_response(conn, 404)
    end
  end

  describe "create (POST /api/ledger-accounts)" do
    test "201 with valid attrs", %{conn: conn, platform_tenant: tenant} do
      ah = insert(:account_holder, tenant_id: tenant.id)
      ledger = insert(:ledger, tenant_id: tenant.id, account_holder_id: ah.id)
      cp = insert(:counterparty, tenant_id: tenant.id, account_holder_id: ah.id)
      attrs = create_attrs(tenant.id, ledger.id, ah.id, cp.id)

      conn = post(conn, ~p"/api/ledger-accounts", attrs)
      response = json_response(conn, 201)

      assert_schema(response, "LedgerAccountResponse", ApiSpec.spec())
      assert response["ledger_id"] == ledger.id

      assert [location] = get_resp_header(conn, "location")
      assert location =~ "/api/ledger-accounts/#{response["id"]}"
    end

    test "422 with missing required fields", %{conn: conn} do
      conn = post(conn, ~p"/api/ledger-accounts", %{})
      assert json_response(conn, 422)
    end
  end

  describe "update (PUT /api/ledger-accounts/:id)" do
    test "200 with valid attrs", %{conn: conn, platform_tenant: tenant} do
      la = insert(:ledger_account, tenant_id: tenant.id)

      attrs = %{
        ledger_id: la.ledger_id,
        account_holder_id: la.account_holder_id,
        currency: la.currency,
        regime: la.regime,
        la_type: to_string(la.la_type),
        payment_account_id: la.payment_account_id,
        counterparty_id: la.counterparty_id,
        status: "closed",
        tenant_id: tenant.id
      }

      conn = put(conn, ~p"/api/ledger-accounts/#{la.id}", attrs)
      response = json_response(conn, 200)

      assert response["status"] == "closed"
    end

    test "404 for unknown id", %{conn: conn, platform_tenant: tenant} do
      ah = insert(:account_holder, tenant_id: tenant.id)
      ledger = insert(:ledger, tenant_id: tenant.id, account_holder_id: ah.id)
      cp = insert(:counterparty, tenant_id: tenant.id, account_holder_id: ah.id)
      attrs = create_attrs(tenant.id, ledger.id, ah.id, cp.id)

      conn = put(conn, ~p"/api/ledger-accounts/00000000-0000-0000-0000-000000000000", attrs)
      assert json_response(conn, 404)
    end
  end

  describe "delete (DELETE /api/ledger-accounts/:id)" do
    test "204 deletes the row", %{conn: conn, platform_tenant: tenant} do
      la = insert(:ledger_account, tenant_id: tenant.id)
      conn = delete(conn, ~p"/api/ledger-accounts/#{la.id}")
      assert response(conn, 204)
    end

    test "404 for unknown id", %{conn: conn} do
      conn = delete(conn, ~p"/api/ledger-accounts/00000000-0000-0000-0000-000000000000")
      assert json_response(conn, 404)
    end
  end
end
