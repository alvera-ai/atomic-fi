defmodule AtomicFiApi.RuleControllerTest do
  # async: false — tests share the on-disk priv/zenrule directory.
  use AtomicFiWeb.ConnCase, async: false

  alias AtomicFi.RulesContext
  alias AtomicFi.RulesTestHelper

  setup :setup_platform_admin_api

  describe "GET /api/rules/:rule_type" do
    test "lists JDM filenames in the folder", %{conn: conn, session: session} do
      name = RulesTestHelper.unique_rule_name()
      RulesTestHelper.register_for_cleanup(:transaction_screening, name)
      :ok = RulesContext.write_rule(session, :transaction_screening, name, Base.encode64("{}"))

      resp =
        conn
        |> get(~p"/api/rules/transaction-screening")
        |> json_response(200)

      assert %{"rules" => names} = resp
      assert name in names
    end

    test "returns 422 for an invalid rule_type slug", %{conn: conn} do
      conn = get(conn, ~p"/api/rules/bogus")
      assert json_response(conn, 422)
    end
  end

  describe "GET /api/rules/:rule_type/:name" do
    test "returns the raw JDM bytes", %{conn: conn, session: session} do
      name = RulesTestHelper.unique_rule_name()
      RulesTestHelper.register_for_cleanup(:transaction_screening, name)
      body = ~s|{"hello":"jdm"}|
      :ok = RulesContext.write_rule(session, :transaction_screening, name, Base.encode64(body))

      conn = get(conn, ~p"/api/rules/transaction-screening/#{name}")

      assert response(conn, 200) == body
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    end

    test "returns 422 for a missing rule", %{conn: conn} do
      conn = get(conn, ~p"/api/rules/transaction-screening/does_not_exist.json")
      assert json_response(conn, 422)
    end
  end

  describe "PUT /api/rules/:rule_type/:name" do
    test "creates a new rule when none exists", %{conn: conn, session: session} do
      name = RulesTestHelper.unique_rule_name()
      RulesTestHelper.register_for_cleanup(:transaction_screening, name)

      conn = put(conn, ~p"/api/rules/transaction-screening/#{name}", %{"x" => 1})
      assert response(conn, 204) == ""

      assert {:ok, bytes} = RulesContext.get_rule(session, :transaction_screening, name)
      assert Jason.decode!(bytes) == %{"x" => 1}
    end

    test "overwrites an existing rule", %{conn: conn, session: session} do
      name = RulesTestHelper.unique_rule_name()
      RulesTestHelper.register_for_cleanup(:transaction_screening, name)
      :ok = RulesContext.write_rule(session, :transaction_screening, name, Base.encode64("{}"))

      conn = put(conn, ~p"/api/rules/transaction-screening/#{name}", %{"y" => 2})
      assert response(conn, 204) == ""

      assert {:ok, bytes} = RulesContext.get_rule(session, :transaction_screening, name)
      assert Jason.decode!(bytes) == %{"y" => 2}
    end
  end

  describe "DELETE /api/rules/:rule_type/:name" do
    test "removes the rule", %{conn: conn, session: session} do
      name = RulesTestHelper.unique_rule_name()
      RulesTestHelper.register_for_cleanup(:transaction_screening, name)
      :ok = RulesContext.write_rule(session, :transaction_screening, name, Base.encode64("{}"))

      conn = delete(conn, ~p"/api/rules/transaction-screening/#{name}")
      assert response(conn, 204) == ""

      assert {:error, :enoent} = RulesContext.get_rule(session, :transaction_screening, name)
    end
  end
end
