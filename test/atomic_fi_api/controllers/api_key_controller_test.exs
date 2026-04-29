defmodule AtomicFiApi.ApiKeyControllerTest do
  use AtomicFiWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import AtomicFi.Factory

  alias AtomicFiApi.ApiSpec

  setup :setup_platform_admin_api

  describe "index (GET /api/api-keys)" do
    test "lists all api keys", %{conn: conn, platform_tenant: platform_tenant} do
      api_key = insert(:api_key, tenant_id: platform_tenant.id)

      conn = get(conn, ~p"/api/api-keys")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "ApiKeyListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert is_list(data)
      assert meta["total_count"] >= 1
      assert Enum.any?(data, fn k -> k["id"] == api_key.id end)
    end

    test "response never exposes key_hash or key_value", %{
      conn: conn,
      platform_tenant: platform_tenant
    } do
      insert(:api_key, tenant_id: platform_tenant.id)

      conn = get(conn, ~p"/api/api-keys")
      response = json_response(conn, 200)

      Enum.each(response["data"], fn key ->
        refute Map.has_key?(key, "key_hash")
        refute Map.has_key?(key, "key_value")
      end)
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/api-keys")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/api-keys/:id)" do
    test "renders api key when id exists", %{conn: conn, platform_tenant: platform_tenant} do
      api_key = insert(:api_key, tenant_id: platform_tenant.id)

      conn = get(conn, ~p"/api/api-keys/#{api_key.id}")
      response = json_response(conn, 200)

      assert_schema(response, "ApiKeyResponse", ApiSpec.spec())
      assert response["id"] == api_key.id
      assert response["name"] == api_key.name
      refute Map.has_key?(response, "key_hash")
      refute Map.has_key?(response, "key_value")
    end

    test "renders 404 when api key does not exist", %{conn: conn} do
      conn = get(conn, ~p"/api/api-keys/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end

    test "renders 422 when id is invalid format", %{conn: conn} do
      conn = get(conn, ~p"/api/api-keys/not-a-uuid")
      assert conn.status == 422
    end
  end

  describe "create (POST /api/api-keys)" do
    test "renders api key with raw_key when data is valid", %{
      conn: conn,
      platform_tenant: platform_tenant
    } do
      role = insert(:role, tenant_id: platform_tenant.id)

      attrs = %{
        name: "ci-production",
        tenant_id: platform_tenant.id,
        role_id: role.id
      }

      conn = post(conn, ~p"/api/api-keys", attrs)
      response = json_response(conn, 201)

      assert_schema(response, "ApiKeyResponse", ApiSpec.spec())
      assert response["name"] == "ci-production"
      assert is_binary(response["id"])
      assert is_binary(response["raw_key"])
      assert String.starts_with?(response["raw_key"], "sk-")
      refute Map.has_key?(response, "key_hash")
      refute Map.has_key?(response, "key_value")

      assert Plug.Conn.get_resp_header(conn, "location") == ["/api/api-keys/#{response["id"]}"]
    end

    test "raw_key is NOT returned on subsequent show", %{
      conn: conn,
      platform_tenant: platform_tenant
    } do
      role = insert(:role, tenant_id: platform_tenant.id)

      attrs = %{
        name: "key-to-fetch",
        tenant_id: platform_tenant.id,
        role_id: role.id
      }

      created = post(conn, ~p"/api/api-keys", attrs) |> json_response(201)

      fetch_conn = get(conn, ~p"/api/api-keys/#{created["id"]}")
      fetched = json_response(fetch_conn, 200)

      assert is_nil(fetched["raw_key"])
    end

    test "renders errors when name is missing", %{conn: conn, platform_tenant: platform_tenant} do
      role = insert(:role, tenant_id: platform_tenant.id)

      attrs = %{
        tenant_id: platform_tenant.id,
        role_id: role.id
      }

      conn = post(conn, ~p"/api/api-keys", attrs)
      response = json_response(conn, 422)

      assert %{"errors" => errors} = response
      assert Enum.any?(errors, fn e -> e["source"]["pointer"] == "/name" end)
    end

    test "renders errors when role_id is missing", %{conn: conn, platform_tenant: platform_tenant} do
      attrs = %{
        name: "no-role",
        tenant_id: platform_tenant.id
      }

      conn = post(conn, ~p"/api/api-keys", attrs)
      assert json_response(conn, 422)
    end
  end

  describe "delete (DELETE /api/api-keys/:id)" do
    test "deletes api key", %{conn: conn, platform_tenant: platform_tenant} do
      api_key = insert(:api_key, tenant_id: platform_tenant.id)

      conn = delete(conn, ~p"/api/api-keys/#{api_key.id}")
      assert response(conn, 204)
    end

    test "renders 404 when api key does not exist", %{conn: conn} do
      conn = delete(conn, ~p"/api/api-keys/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes api-key endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"paths" => paths} = response
      assert paths["/api/api-keys"]
      assert paths["/api/api-keys"]["get"]
      assert paths["/api/api-keys"]["post"]
      assert paths["/api/api-keys/{id}"]
      assert paths["/api/api-keys/{id}"]["get"]
      assert paths["/api/api-keys/{id}"]["delete"]

      # No PUT — API keys are rotated by delete + create
      refute paths["/api/api-keys/{id}"]["put"]
    end

    test "OpenAPI spec includes api-key schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => schemas}} = response
      assert schemas["ApiKeyRequest"]
      assert schemas["ApiKeyResponse"]
      assert schemas["ApiKeyListResponse"]

      # Request schema must NOT include key_hash/key_value — those are server-generated
      req_props = schemas["ApiKeyRequest"]["properties"]
      refute Map.has_key?(req_props, "key_hash")
      refute Map.has_key?(req_props, "key_value")

      # Response schema must NOT expose key_hash/key_value
      resp_props = schemas["ApiKeyResponse"]["properties"]
      refute Map.has_key?(resp_props, "key_hash")
      refute Map.has_key?(resp_props, "key_value")
      assert Map.has_key?(resp_props, "raw_key")
    end
  end
end
