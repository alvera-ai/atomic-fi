defmodule AtomicFiApi.CustomerControllerTest do
  use AtomicFiWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import AtomicFi.Factory

  alias AtomicFiApi.ApiSpec

  setup :setup_platform_admin_api

  describe "index (GET /api/customers)" do
    test "lists customers", %{conn: conn, platform_tenant: tenant} do
      customer = insert(:customer, tenant_id: tenant.id)

      conn = get(conn, ~p"/api/customers")
      response = json_response(conn, 200)

      assert_schema(response, "CustomerListResponse", ApiSpec.spec())
      assert %{"data" => data, "meta" => meta} = response
      assert meta["total_count"] >= 1
      assert Enum.any?(data, fn c -> c["id"] == customer.id end)
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/customers")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/customers/:id)" do
    test "renders customer when id exists", %{conn: conn, platform_tenant: tenant} do
      customer = insert(:customer, tenant_id: tenant.id)

      conn = get(conn, ~p"/api/customers/#{customer.id}")
      response = json_response(conn, 200)

      assert_schema(response, "CustomerResponse", ApiSpec.spec())
      assert response["id"] == customer.id
      assert response["name"] == customer.name
    end

    test "renders 404 when customer does not exist", %{conn: conn} do
      conn = get(conn, ~p"/api/customers/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end

    test "renders 422 when id is invalid format", %{conn: conn} do
      conn = get(conn, ~p"/api/customers/not-a-uuid")
      assert conn.status == 422
    end
  end

  describe "create (POST /api/customers)" do
    test "creates customer with valid data", %{conn: conn, platform_tenant: tenant} do
      attrs = %{
        name: "Acme Corp",
        slug: "acme-corp-#{System.unique_integer([:positive])}",
        description: "Test customer",
        status: "active",
        metadata: %{"tier" => "enterprise"},
        tenant_id: tenant.id
      }

      conn = post(conn, ~p"/api/customers", attrs)
      response = json_response(conn, 201)

      assert_schema(response, "CustomerResponse", ApiSpec.spec())
      assert response["name"] == "Acme Corp"
      assert response["status"] == "active"
      assert is_binary(response["id"])

      assert Plug.Conn.get_resp_header(conn, "location") == [
               "/api/customers/#{response["id"]}"
             ]
    end

    test "renders errors when name is missing", %{conn: conn, platform_tenant: tenant} do
      attrs = %{tenant_id: tenant.id}

      conn = post(conn, ~p"/api/customers", attrs)
      response = json_response(conn, 422)

      assert %{"errors" => errors} = response
      assert Enum.any?(errors, fn e -> e["source"]["pointer"] == "/name" end)
    end
  end

  describe "update (PUT /api/customers/:id)" do
    test "updates customer with valid data", %{conn: conn, platform_tenant: tenant} do
      customer = insert(:customer, tenant_id: tenant.id, name: "Original")

      attrs = %{
        name: "Updated",
        slug: customer.slug,
        description: "Updated description",
        status: "suspended",
        metadata: %{},
        tenant_id: tenant.id
      }

      conn = put(conn, ~p"/api/customers/#{customer.id}", attrs)
      response = json_response(conn, 200)

      assert_schema(response, "CustomerResponse", ApiSpec.spec())
      assert response["id"] == customer.id
      assert response["name"] == "Updated"
      assert response["status"] == "suspended"
    end

    test "renders 404 when customer does not exist", %{conn: conn, platform_tenant: tenant} do
      attrs = %{name: "x", tenant_id: tenant.id}

      conn = put(conn, ~p"/api/customers/#{Ecto.UUID.generate()}", attrs)
      assert json_response(conn, 404)
    end
  end

  describe "delete (DELETE /api/customers/:id)" do
    test "deletes customer", %{conn: conn, platform_tenant: tenant} do
      customer = insert(:customer, tenant_id: tenant.id)

      conn = delete(conn, ~p"/api/customers/#{customer.id}")
      assert response(conn, 204)
    end

    test "renders 404 when customer does not exist", %{conn: conn} do
      conn = delete(conn, ~p"/api/customers/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes customer endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"paths" => paths} = response
      assert paths["/api/customers"]
      assert paths["/api/customers"]["get"]
      assert paths["/api/customers"]["post"]
      assert paths["/api/customers/{id}"]
      assert paths["/api/customers/{id}"]["get"]
      assert paths["/api/customers/{id}"]["put"]
      assert paths["/api/customers/{id}"]["delete"]
    end

    test "OpenAPI spec includes customer schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => schemas}} = response
      assert schemas["CustomerRequest"]
      assert schemas["CustomerResponse"]
      assert schemas["CustomerListResponse"]
    end
  end
end
