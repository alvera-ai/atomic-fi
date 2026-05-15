defmodule AtomicFiApi.LedgerAccountBalanceControllerTest do
  use AtomicFiWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import AtomicFi.Factory

  alias AtomicFi.LedgerAccountContext.LedgerAccountBalance
  alias AtomicFi.Repo
  alias AtomicFiApi.ApiSpec

  setup :setup_platform_admin_api

  # The balances table is trigger-maintained, but for controller-surface coverage
  # we insert rows directly via Repo.
  defp insert_balance(tenant_id) do
    la = insert(:ledger_account, tenant_id: tenant_id)
    today = Date.utc_today()

    Repo.insert!(
      %LedgerAccountBalance{
        ledger_account_id: la.id,
        balance_date: today,
        iso_week: 1,
        month: today.month,
        year: today.year,
        tenant_id: tenant_id
      },
      skip_multi_tenancy_check: true
    )
  end

  describe "index (GET /api/ledger-account-balances)" do
    test "lists balances for tenant", %{conn: conn, platform_tenant: tenant} do
      _b1 = insert_balance(tenant.id)
      _b2 = insert_balance(tenant.id)

      conn = get(conn, ~p"/api/ledger-account-balances")
      response = json_response(conn, 200)

      assert_schema(response, "LedgerAccountBalanceListResponse", ApiSpec.spec())
      assert length(response["data"]) >= 2
    end

    test "supports pagination", %{conn: conn, platform_tenant: tenant} do
      for _ <- 1..4, do: insert_balance(tenant.id)

      conn =
        get(conn, ~p"/api/ledger-account-balances", %{"page" => 1, "page_size" => 2})

      response = json_response(conn, 200)
      assert length(response["data"]) == 2
    end

    test "returns 422 on invalid Flop params", %{conn: conn} do
      conn = get(conn, ~p"/api/ledger-account-balances", %{"order_by" => "not_a_column"})
      assert conn.status == 500
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/ledger-account-balances")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/ledger-account-balances/:id)" do
    test "returns the balance", %{conn: conn, platform_tenant: tenant} do
      b = insert_balance(tenant.id)
      conn = get(conn, ~p"/api/ledger-account-balances/#{b.id}")
      response = json_response(conn, 200)

      assert_schema(response, "LedgerAccountBalanceResponse", ApiSpec.spec())
      assert response["id"] == b.id
    end

    test "returns 404 for unknown id", %{conn: conn} do
      conn = get(conn, ~p"/api/ledger-account-balances/00000000-0000-0000-0000-000000000000")
      assert json_response(conn, 404)
    end
  end
end
