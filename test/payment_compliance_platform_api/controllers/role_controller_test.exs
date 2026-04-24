defmodule PaymentCompliancePlatformApi.RoleControllerTest do
  use PaymentCompliancePlatformWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import PaymentCompliancePlatform.Factory

  alias PaymentCompliancePlatformApi.ApiSpec

  setup :setup_platform_admin_api

  describe "index (GET /api/roles)" do
    test "lists all roles", %{conn: conn, platform_tenant: platform_tenant} do
      role = insert(:role, tenant_id: platform_tenant.id)

      conn = get(conn, ~p"/api/roles")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "RoleListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert is_list(data)
      assert meta["total_count"] >= 1
      assert Enum.any?(data, fn r -> r["id"] == role.id end)
    end

    test "supports pagination", %{conn: conn, platform_tenant: platform_tenant} do
      for _i <- 1..10 do
        insert(:role, tenant_id: platform_tenant.id)
      end

      conn = get(conn, ~p"/api/roles", %{"page" => 1, "page_size" => 5})
      response = json_response(conn, 200)

      assert_schema(response, "RoleListResponse", ApiSpec.spec())
      assert length(response["data"]) == 5
      assert response["meta"]["page_size"] == 5
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/roles")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/roles/:id)" do
    test "renders role when id exists", %{conn: conn, platform_tenant: platform_tenant} do
      role = insert(:role, tenant_id: platform_tenant.id)

      conn = get(conn, ~p"/api/roles/#{role.id}")
      response = json_response(conn, 200)

      assert_schema(response, "RoleResponse", ApiSpec.spec())
      assert response["id"] == role.id
      assert response["name"] == role.name
    end

    test "renders 404 when role does not exist", %{conn: conn} do
      conn = get(conn, ~p"/api/roles/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end

    test "renders 422 when id is invalid format", %{conn: conn} do
      conn = get(conn, ~p"/api/roles/not-a-uuid")
      assert conn.status == 422
    end
  end

  describe "create (POST /api/roles)" do
    test "renders role when data is valid", %{conn: conn, platform_tenant: platform_tenant} do
      attrs = %{
        name: "compliance_reviewer",
        description: "Reviews compliance screenings",
        metadata: %{},
        tenant_id: platform_tenant.id
      }

      conn = post(conn, ~p"/api/roles", attrs)
      response = json_response(conn, 201)

      assert_schema(response, "RoleResponse", ApiSpec.spec())
      assert response["name"] == "compliance_reviewer"
      assert is_binary(response["id"])

      assert Plug.Conn.get_resp_header(conn, "location") == ["/api/roles/#{response["id"]}"]
    end

    test "renders errors when name is missing", %{conn: conn, platform_tenant: platform_tenant} do
      attrs = %{
        description: "no name here",
        metadata: %{},
        tenant_id: platform_tenant.id
      }

      conn = post(conn, ~p"/api/roles", attrs)
      response = json_response(conn, 422)

      assert %{"errors" => errors} = response
      assert Enum.any?(errors, fn e -> e["source"]["pointer"] == "/name" end)
    end

    test "rejects reserved role names", %{conn: conn, platform_tenant: platform_tenant} do
      attrs = %{
        name: "root",
        description: "attempting reserved name",
        metadata: %{},
        tenant_id: platform_tenant.id
      }

      conn = post(conn, ~p"/api/roles", attrs)
      assert json_response(conn, 422)
    end
  end

  describe "update (PUT /api/roles/:id)" do
    setup %{platform_tenant: platform_tenant} do
      role = insert(:role, tenant_id: platform_tenant.id)
      %{role: role}
    end

    test "renders role when data is valid", %{
      conn: conn,
      role: role,
      platform_tenant: platform_tenant
    } do
      attrs = %{
        name: "updated_role_name",
        description: "updated description",
        metadata: %{"updated" => true},
        tenant_id: platform_tenant.id
      }

      conn = put(conn, ~p"/api/roles/#{role.id}", attrs)
      response = json_response(conn, 200)

      assert_schema(response, "RoleResponse", ApiSpec.spec())
      assert response["name"] == "updated_role_name"
      assert response["id"] == role.id
    end

    test "renders 404 when role does not exist", %{
      conn: conn,
      platform_tenant: platform_tenant
    } do
      attrs = %{
        name: "whatever",
        description: "x",
        metadata: %{},
        tenant_id: platform_tenant.id
      }

      conn = put(conn, ~p"/api/roles/#{Ecto.UUID.generate()}", attrs)
      assert json_response(conn, 404)
    end
  end

  describe "delete (DELETE /api/roles/:id)" do
    test "deletes role", %{conn: conn, platform_tenant: platform_tenant} do
      role = insert(:role, tenant_id: platform_tenant.id)

      conn = delete(conn, ~p"/api/roles/#{role.id}")
      assert response(conn, 204)
    end

    test "renders 404 when role does not exist", %{conn: conn} do
      conn = delete(conn, ~p"/api/roles/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes role endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"paths" => paths} = response
      assert paths["/api/roles"]
      assert paths["/api/roles"]["get"]
      assert paths["/api/roles"]["post"]
      assert paths["/api/roles/{id}"]
      assert paths["/api/roles/{id}"]["get"]
      assert paths["/api/roles/{id}"]["put"]
      assert paths["/api/roles/{id}"]["delete"]
    end

    test "OpenAPI spec includes role schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => schemas}} = response
      assert schemas["RoleRequest"]
      assert schemas["RoleResponse"]
      assert schemas["RoleListResponse"]
    end
  end
end
