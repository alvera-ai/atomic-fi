defmodule PaymentCompliancePlatformApi.BlocklistEntryControllerTest do
  use PaymentCompliancePlatformWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import PaymentCompliancePlatform.Factory

  alias PaymentCompliancePlatformApi.ApiSpec

  setup :setup_platform_admin_api

  describe "index (GET /api/blocklist-entries)" do
    test "lists all blocklist entries", %{conn: conn, platform_tenant: platform_tenant} do
      entry = insert(:blocklist_entry, tenant_id: platform_tenant.id)

      conn = get(conn, ~p"/api/blocklist-entries")
      response = json_response(conn, 200)

      assert_schema(response, "BlocklistEntryListResponse", ApiSpec.spec())
      assert %{"data" => data, "meta" => meta} = response
      assert is_list(data)
      assert meta["total_count"] >= 1
      assert Enum.any?(data, fn e -> e["id"] == entry.id end)
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/blocklist-entries")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/blocklist-entries/:id)" do
    test "renders entry when id exists", %{conn: conn, platform_tenant: platform_tenant} do
      entry = insert(:blocklist_entry, tenant_id: platform_tenant.id)

      conn = get(conn, ~p"/api/blocklist-entries/#{entry.id}")
      response = json_response(conn, 200)

      assert_schema(response, "BlocklistEntryResponse", ApiSpec.spec())
      assert response["id"] == entry.id
      assert response["term"] == entry.term
    end

    test "renders 404 when entry does not exist", %{conn: conn} do
      conn = get(conn, ~p"/api/blocklist-entries/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end

    test "renders 422 when id is invalid format", %{conn: conn} do
      conn = get(conn, ~p"/api/blocklist-entries/not-a-uuid")
      assert conn.status == 422
    end
  end

  describe "create (POST /api/blocklist-entries)" do
    test "creates entry with valid data", %{conn: conn, platform_tenant: platform_tenant} do
      attrs = %{
        scope: "first_name",
        entry_type: "exact",
        term: "blocked_person",
        reason: "Test create",
        active: true,
        tenant_id: platform_tenant.id
      }

      conn = post(conn, ~p"/api/blocklist-entries", attrs)
      response = json_response(conn, 201)

      assert_schema(response, "BlocklistEntryResponse", ApiSpec.spec())
      assert response["term"] == "blocked_person"
      assert response["scope"] == "first_name"
      assert response["entry_type"] == "exact"
      assert is_binary(response["id"])

      assert Plug.Conn.get_resp_header(conn, "location") == [
               "/api/blocklist-entries/#{response["id"]}"
             ]
    end

    test "renders errors when term is missing", %{conn: conn, platform_tenant: platform_tenant} do
      attrs = %{
        scope: "first_name",
        entry_type: "exact",
        tenant_id: platform_tenant.id
      }

      conn = post(conn, ~p"/api/blocklist-entries", attrs)
      response = json_response(conn, 422)

      assert %{"errors" => errors} = response
      assert Enum.any?(errors, fn e -> e["source"]["pointer"] == "/term" end)
    end

    test "renders errors when regex term is invalid", %{
      conn: conn,
      platform_tenant: platform_tenant
    } do
      attrs = %{
        scope: "company_name",
        entry_type: "regex",
        term: "[invalid(regex",
        tenant_id: platform_tenant.id
      }

      conn = post(conn, ~p"/api/blocklist-entries", attrs)
      assert json_response(conn, 422)
    end
  end

  describe "update (PUT /api/blocklist-entries/:id)" do
    setup %{platform_tenant: platform_tenant} do
      entry =
        insert(:blocklist_entry,
          tenant_id: platform_tenant.id,
          term: "original_term",
          scope: :first_name,
          entry_type: :exact
        )

      %{entry: entry}
    end

    test "updates entry with valid data", %{
      conn: conn,
      entry: entry,
      platform_tenant: platform_tenant
    } do
      attrs = %{
        scope: "last_name",
        entry_type: "exact",
        term: "updated_term",
        reason: "Updated reason",
        active: false,
        tenant_id: platform_tenant.id
      }

      conn = put(conn, ~p"/api/blocklist-entries/#{entry.id}", attrs)
      response = json_response(conn, 200)

      assert_schema(response, "BlocklistEntryResponse", ApiSpec.spec())
      assert response["id"] == entry.id
      assert response["term"] == "updated_term"
      assert response["scope"] == "last_name"
      assert response["active"] == false
    end

    test "renders 404 when entry does not exist", %{
      conn: conn,
      platform_tenant: platform_tenant
    } do
      attrs = %{
        scope: "first_name",
        entry_type: "exact",
        term: "any",
        tenant_id: platform_tenant.id
      }

      conn = put(conn, ~p"/api/blocklist-entries/#{Ecto.UUID.generate()}", attrs)
      assert json_response(conn, 404)
    end
  end

  describe "delete (DELETE /api/blocklist-entries/:id)" do
    test "deletes entry", %{conn: conn, platform_tenant: platform_tenant} do
      entry = insert(:blocklist_entry, tenant_id: platform_tenant.id)

      conn = delete(conn, ~p"/api/blocklist-entries/#{entry.id}")
      assert response(conn, 204)
    end

    test "renders 404 when entry does not exist", %{conn: conn} do
      conn = delete(conn, ~p"/api/blocklist-entries/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes blocklist entry endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"paths" => paths} = response
      assert paths["/api/blocklist-entries"]
      assert paths["/api/blocklist-entries"]["get"]
      assert paths["/api/blocklist-entries"]["post"]
      assert paths["/api/blocklist-entries/{id}"]
      assert paths["/api/blocklist-entries/{id}"]["get"]
      assert paths["/api/blocklist-entries/{id}"]["put"]
      assert paths["/api/blocklist-entries/{id}"]["delete"]
    end

    test "OpenAPI spec includes blocklist entry schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => schemas}} = response
      assert schemas["BlocklistEntryRequest"]
      assert schemas["BlocklistEntryResponse"]
      assert schemas["BlocklistEntryListResponse"]
    end
  end
end
