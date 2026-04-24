defmodule PaymentCompliancePlatformApi.UserControllerTest do
  use PaymentCompliancePlatformWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import PaymentCompliancePlatform.Factory

  alias PaymentCompliancePlatformApi.ApiSpec

  setup :setup_platform_admin_api

  describe "index (GET /api/users)" do
    test "lists all users", %{conn: conn, platform_tenant: platform_tenant} do
      user = insert(:user, tenant_id: platform_tenant.id)

      conn = get(conn, ~p"/api/users")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "UserListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert is_list(data)
      assert meta["total_count"] >= 1
      assert Enum.any?(data, fn u -> u["id"] == user.id end)
    end

    test "supports pagination", %{conn: conn, platform_tenant: platform_tenant} do
      for i <- 1..10 do
        insert(:user, tenant_id: platform_tenant.id, email: "paginate-#{i}@example.com")
      end

      conn = get(conn, ~p"/api/users", %{"page" => 1, "page_size" => 5})
      response = json_response(conn, 200)

      assert_schema(response, "UserListResponse", ApiSpec.spec())
      assert length(response["data"]) == 5
      assert response["meta"]["page_size"] == 5
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/users")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/users/:id)" do
    test "renders user when id exists", %{conn: conn, platform_tenant: platform_tenant} do
      user = insert(:user, tenant_id: platform_tenant.id)

      conn = get(conn, ~p"/api/users/#{user.id}")
      response = json_response(conn, 200)

      assert_schema(response, "UserResponse", ApiSpec.spec())
      assert response["id"] == user.id
      assert response["email"] == user.email
    end

    test "renders 404 when user does not exist", %{conn: conn} do
      conn = get(conn, ~p"/api/users/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end

    test "renders 422 when id is invalid format", %{conn: conn} do
      conn = get(conn, ~p"/api/users/not-a-uuid")
      assert conn.status == 422
    end
  end

  describe "create (POST /api/users)" do
    test "renders user when data is valid", %{conn: conn, platform_tenant: platform_tenant} do
      attrs = %{
        email: "new@example.com",
        hashed_password: Bcrypt.hash_pwd_salt("secret123"),
        confirmed_at: "2026-04-20T12:00:00.000000Z",
        tenant_id: platform_tenant.id
      }

      conn = post(conn, ~p"/api/users", attrs)
      response = json_response(conn, 201)

      assert_schema(response, "UserResponse", ApiSpec.spec())
      assert response["email"] == "new@example.com"
      assert is_binary(response["id"])

      assert Plug.Conn.get_resp_header(conn, "location") == ["/api/users/#{response["id"]}"]
    end

    test "renders errors when email is missing", %{conn: conn, platform_tenant: platform_tenant} do
      attrs = %{
        hashed_password: "hashed",
        confirmed_at: "2026-04-20T12:00:00.000000Z",
        tenant_id: platform_tenant.id
      }

      conn = post(conn, ~p"/api/users", attrs)
      response = json_response(conn, 422)

      assert %{"errors" => errors} = response
      assert Enum.any?(errors, fn e -> e["source"]["pointer"] == "/email" end)
    end

    test "renders errors when tenant_id is missing", %{conn: conn} do
      attrs = %{
        email: "x@example.com",
        hashed_password: "hashed",
        confirmed_at: "2026-04-20T12:00:00.000000Z"
      }

      conn = post(conn, ~p"/api/users", attrs)
      assert json_response(conn, 422)
    end
  end

  describe "update (PUT /api/users/:id)" do
    setup %{platform_tenant: platform_tenant} do
      user = insert(:user, tenant_id: platform_tenant.id, email: "original@example.com")
      %{user: user}
    end

    test "renders user when data is valid", %{
      conn: conn,
      user: user,
      platform_tenant: platform_tenant
    } do
      attrs = %{
        email: "updated@example.com",
        hashed_password: user.hashed_password,
        confirmed_at: "2026-04-21T12:00:00.000000Z",
        tenant_id: platform_tenant.id
      }

      conn = put(conn, ~p"/api/users/#{user.id}", attrs)
      response = json_response(conn, 200)

      assert_schema(response, "UserResponse", ApiSpec.spec())
      assert response["email"] == "updated@example.com"
      assert response["id"] == user.id
    end

    test "renders 404 when user does not exist", %{
      conn: conn,
      platform_tenant: platform_tenant
    } do
      attrs = %{
        email: "x@example.com",
        hashed_password: "hashed",
        confirmed_at: "2026-04-20T12:00:00.000000Z",
        tenant_id: platform_tenant.id
      }

      conn = put(conn, ~p"/api/users/#{Ecto.UUID.generate()}", attrs)
      assert json_response(conn, 404)
    end
  end

  describe "delete (DELETE /api/users/:id)" do
    test "deletes user", %{conn: conn, platform_tenant: platform_tenant} do
      user = insert(:user, tenant_id: platform_tenant.id)

      conn = delete(conn, ~p"/api/users/#{user.id}")
      assert response(conn, 204)
    end

    test "renders 404 when user does not exist", %{conn: conn} do
      conn = delete(conn, ~p"/api/users/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes user endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"paths" => paths} = response
      assert paths["/api/users"]
      assert paths["/api/users"]["get"]
      assert paths["/api/users"]["post"]
      assert paths["/api/users/{id}"]
      assert paths["/api/users/{id}"]["get"]
      assert paths["/api/users/{id}"]["put"]
      assert paths["/api/users/{id}"]["delete"]
    end

    test "OpenAPI spec includes user schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => schemas}} = response
      assert schemas["UserRequest"]
      assert schemas["UserResponse"]
      assert schemas["UserListResponse"]
    end
  end
end
