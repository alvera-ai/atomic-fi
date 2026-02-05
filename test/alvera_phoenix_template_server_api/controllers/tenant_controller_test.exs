defmodule AlveraPhoenixTemplateServerApi.TenantControllerTest do
  use AlveraPhoenixTemplateServerWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import AlveraPhoenixTemplateServer.Factory

  alias AlveraPhoenixTemplateServer.TenantContext
  alias AlveraPhoenixTemplateServerApi.ApiSpec

  @create_attrs %{
    name: "Test Tenant",
    tenant_type: "standard",
    status: "active",
    metadata: %{}
  }
  @update_attrs %{
    name: "Updated Tenant",
    tenant_type: "standard",
    status: "suspended",
    metadata: %{"updated" => true}
  }
  @invalid_attrs %{
    name: nil,
    tenant_type: nil,
    status: nil
  }

  # Use the platform_admin_api key from test_migrations for positive tests
  setup :setup_platform_admin_api

  describe "index (GET /api/tenants)" do
    test "lists all tenants", %{conn: conn, platform_tenant: platform_tenant} do
      tenant1 = insert(:tenant, name: "Tenant A", tenant_type: :standard)
      tenant2 = insert(:tenant, name: "Tenant B", tenant_type: :standard)

      conn = get(conn, ~p"/api/tenants")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      # Validate entire list response against OpenAPI schema
      assert_schema(response, "TenantListResponse", api_spec)

      # Business logic assertions
      assert %{
               "data" => data,
               "meta" => meta
             } = response

      assert is_list(data)
      assert length(data) >= 3
      assert meta["total_count"] >= 3

      tenant_ids = Enum.map(data, & &1["id"])
      assert platform_tenant.id in tenant_ids
      assert tenant1.id in tenant_ids
      assert tenant2.id in tenant_ids
    end

    test "supports pagination", %{conn: conn} do
      # Create multiple tenants
      for i <- 1..15 do
        insert(:tenant, name: "Tenant #{i}", tenant_type: :standard)
      end

      # Request first page with page_size=5
      conn = get(conn, ~p"/api/tenants", %{"page" => 1, "page_size" => 5})
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      # Validate entire list response against OpenAPI schema
      assert_schema(response, "TenantListResponse", api_spec)

      # Business logic assertions
      assert %{
               "data" => data,
               "meta" => meta
             } = response

      assert length(data) == 5
      assert meta["page"] == 1
      assert meta["page_size"] == 5
      assert meta["total_count"] >= 15
    end

    test "supports sorting by name ascending", %{conn: conn} do
      insert(:tenant, name: "Zebra Tenant", tenant_type: :standard)
      insert(:tenant, name: "Alpha Tenant", tenant_type: :standard)

      conn = get(conn, ~p"/api/tenants", %{"order_by" => "name", "order_directions" => "asc"})
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      # Validate entire list response against OpenAPI schema
      assert_schema(response, "TenantListResponse", api_spec)

      # Business logic assertions
      assert %{"data" => data} = response
      names = Enum.map(data, & &1["name"])

      # Alpha should come before Zebra when sorted
      alpha_index = Enum.find_index(names, &(&1 == "Alpha Tenant"))
      zebra_index = Enum.find_index(names, &(&1 == "Zebra Tenant"))

      if alpha_index && zebra_index do
        assert alpha_index < zebra_index
      end
    end

    test "supports sorting by name descending", %{conn: conn} do
      insert(:tenant, name: "Alpha Tenant", tenant_type: :standard)
      insert(:tenant, name: "Zebra Tenant", tenant_type: :standard)

      conn = get(conn, ~p"/api/tenants", %{"order_by" => "name", "order_directions" => "desc"})
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      # Validate entire list response against OpenAPI schema
      assert_schema(response, "TenantListResponse", api_spec)

      # Business logic assertions
      assert %{"data" => data} = response
      names = Enum.map(data, & &1["name"])

      # Zebra should come before Alpha when sorted descending
      alpha_index = Enum.find_index(names, &(&1 == "Alpha Tenant"))
      zebra_index = Enum.find_index(names, &(&1 == "Zebra Tenant"))

      if alpha_index && zebra_index do
        assert zebra_index < alpha_index
      end
    end

    test "returns 401 without API key", %{} do
      # Build connection without API key
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/tenants")

      assert json_response(conn, 401)
    end

    test "returns 401 with invalid API key", %{} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", "invalid_key")
        |> get(~p"/api/tenants")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/tenants/:id)" do
    test "renders tenant when id exists", %{conn: conn} do
      tenant = insert(:tenant, name: "Show Tenant", tenant_type: :standard)

      conn = get(conn, ~p"/api/tenants/#{tenant.id}")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      # Validate full response against OpenAPI schema
      assert_schema(response, "TenantResponse", api_spec)

      # Business logic assertions
      assert %{
               "id" => id,
               "name" => "Show Tenant",
               "tenant_type" => "standard"
             } = response

      assert id == tenant.id
    end

    test "renders tenant with all fields", %{conn: conn} do
      tenant =
        insert(:tenant,
          name: "Complete Tenant",
          slug: "complete-tenant",
          status: :active,
          tenant_type: :standard,
          metadata: %{"key" => "value"}
        )

      conn = get(conn, ~p"/api/tenants/#{tenant.id}")
      response = json_response(conn, 200)

      assert %{
               "id" => _id,
               "name" => "Complete Tenant",
               "slug" => "complete-tenant",
               "status" => "active",
               "tenant_type" => "standard",
               "metadata" => %{"key" => "value"},
               "inserted_at" => _,
               "updated_at" => _
             } = response
    end

    test "renders 404 when tenant does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()

      conn = get(conn, ~p"/api/tenants/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "renders 422 when id is invalid format", %{conn: conn} do
      # OpenApiSpex validates UUID format and returns 422
      conn = get(conn, ~p"/api/tenants/invalid-uuid")
      assert conn.status == 422
    end

    test "returns 401 without API key", %{} do
      tenant = insert(:tenant)

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/tenants/#{tenant.id}")

      assert json_response(conn, 401)
    end
  end

  describe "create (POST /api/tenants)" do
    test "renders tenant when data is valid", %{conn: conn} do
      conn = post(conn, ~p"/api/tenants", @create_attrs)
      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      # Validate full response against OpenAPI schema
      assert_schema(response, "TenantResponse", api_spec)

      # Business logic assertions
      assert %{
               "id" => id,
               "name" => "Test Tenant",
               "tenant_type" => "standard",
               "status" => "active"
             } = response

      assert is_binary(id)

      # Verify Location header
      assert Plug.Conn.get_resp_header(conn, "location") == ["/api/tenants/#{id}"]
    end

    test "creates tenant with minimal required fields", %{conn: conn} do
      minimal_attrs = %{
        name: "Minimal Tenant",
        status: "active",
        tenant_type: "standard"
      }

      conn = post(conn, ~p"/api/tenants", minimal_attrs)
      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      # Validate full response against OpenAPI schema
      assert_schema(response, "TenantResponse", api_spec)

      # Business logic assertions
      assert %{
               "id" => _id,
               "name" => "Minimal Tenant",
               "tenant_type" => "standard"
             } = response
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/api/tenants", @invalid_attrs)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert is_list(errors)
      assert length(errors) > 0
    end

    test "renders errors when name is missing", %{conn: conn} do
      attrs = %{tenant_type: "standard", status: "active"}
      conn = post(conn, ~p"/api/tenants", attrs)

      response = json_response(conn, 422)
      assert %{"errors" => errors} = response
      assert Enum.any?(errors, fn error -> error["source"]["pointer"] == "/name" end)
    end

    test "renders errors when tenant_type is missing", %{conn: conn} do
      attrs = %{name: "Test", status: "active"}
      conn = post(conn, ~p"/api/tenants", attrs)

      response = json_response(conn, 422)
      assert %{"errors" => errors} = response

      assert Enum.any?(errors, fn error -> error["source"]["pointer"] == "/tenant_type" end)
    end

    test "renders errors when tenant_type is invalid", %{conn: conn} do
      attrs = %{name: "Test", tenant_type: "invalid_type", status: "active"}
      conn = post(conn, ~p"/api/tenants", attrs)

      assert json_response(conn, 422)
    end

    test "prevents creating platform tenant via API", %{conn: conn} do
      attrs = %{
        name: "Platform Tenant",
        tenant_type: "platform",
        status: "active"
      }

      conn = post(conn, ~p"/api/tenants", attrs)

      response = json_response(conn, 422)
      assert %{"errors" => errors} = response

      # Should have validation error for platform tenant_type
      assert Enum.any?(errors, fn error ->
               error["source"]["pointer"] == "/tenant_type"
             end)
    end

    test "returns 401 without API key", %{} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/tenants", %{"tenant" => @create_attrs})

      assert json_response(conn, 401)
    end

    test "returns 403 with non-platform_admin_api role", %{
      platform_tenant: platform_tenant,
      session: platform_session
    } do
      # Create a different role (not platform_admin_api)
      tenant_admin_role =
        build(:role,
          name: "tenant_admin",
          tenant_id: platform_tenant.id
        )
        |> AlveraPhoenixTemplateServer.Repo.insert!(skip_multi_tenancy_check: true)

      # Generate API key with proper encryption through context
      raw_api_key = "test_api_key_#{:crypto.strong_rand_bytes(16) |> Base.encode64()}"
      key_hash = :crypto.hash(:sha256, raw_api_key) |> Base.encode16(case: :lower)
      encrypted_key = AlveraPhoenixTemplateServer.Vault.encrypt!(raw_api_key)

      {:ok, api_key} =
        AlveraPhoenixTemplateServer.ApiKeyContext.create_api_key(platform_session, %{
          name: "Test API Key",
          key_hash: key_hash,
          key_value: encrypted_key,
          role_id: tenant_admin_role.id,
          tenant_id: platform_tenant.id
        })

      session =
        build(:session,
          type: :api,
          api_key_id: api_key.id,
          role_id: tenant_admin_role.id,
          tenant_id: platform_tenant.id
        )
        |> AlveraPhoenixTemplateServer.Repo.insert!(skip_multi_tenancy_check: true)

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-api-key", raw_api_key)
        |> assign(:api_session, session)
        |> post(~p"/api/tenants", @create_attrs)

      assert json_response(conn, 403)
    end
  end

  describe "update (PUT /api/tenants/:id)" do
    setup [:create_tenant]

    test "renders tenant when data is valid", %{conn: conn, tenant: tenant} do
      conn = put(conn, ~p"/api/tenants/#{tenant.id}", @update_attrs)
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      # Validate full response against OpenAPI schema
      assert_schema(response, "TenantResponse", api_spec)

      # Business logic assertions
      assert %{
               "id" => id,
               "name" => "Updated Tenant",
               "status" => "suspended"
             } = response

      assert id == tenant.id
    end

    test "updates tenant with metadata", %{conn: conn, tenant: tenant} do
      attrs = %{
        name: tenant.name,
        tenant_type: Atom.to_string(tenant.tenant_type),
        status: Atom.to_string(tenant.status),
        metadata: %{"custom_field" => "value", "another" => 123}
      }

      conn = put(conn, ~p"/api/tenants/#{tenant.id}", attrs)
      response = json_response(conn, 200)

      assert %{
               "metadata" => %{
                 "custom_field" => "value",
                 "another" => 123
               }
             } = response
    end



    test "renders errors when data is invalid", %{conn: conn, tenant: tenant} do
      conn = put(conn, ~p"/api/tenants/#{tenant.id}", @invalid_attrs)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert is_list(errors)
      assert length(errors) > 0
    end

    test "renders errors when name is blank", %{conn: conn, tenant: tenant} do
      attrs = %{
        name: "",
        tenant_type: Atom.to_string(tenant.tenant_type),
        status: Atom.to_string(tenant.status)
      }

      conn = put(conn, ~p"/api/tenants/#{tenant.id}", attrs)

      response = json_response(conn, 422)
      assert %{"errors" => errors} = response
      assert Enum.any?(errors, fn error -> error["source"]["pointer"] == "/name" end)
    end

    test "renders 404 when tenant does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()

      conn =
        put(conn, ~p"/api/tenants/#{non_existent_id}", @update_attrs)

      assert json_response(conn, 404)
    end

    test "returns 401 without API key", %{tenant: tenant} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/tenants/#{tenant.id}", %{"tenant" => @update_attrs})

      assert json_response(conn, 401)
    end

    test "returns 403 with non-platform_admin_api role", %{
      platform_tenant: platform_tenant,
      session: platform_session,
      tenant: tenant
    } do
      # Create a different role (not platform_admin_api)
      tenant_admin_role =
        build(:role,
          name: "tenant_admin",
          tenant_id: platform_tenant.id
        )
        |> AlveraPhoenixTemplateServer.Repo.insert!(skip_multi_tenancy_check: true)

      # Generate API key with proper encryption through context
      raw_api_key = "test_api_key_#{:crypto.strong_rand_bytes(16) |> Base.encode64()}"
      key_hash = :crypto.hash(:sha256, raw_api_key) |> Base.encode16(case: :lower)
      encrypted_key = AlveraPhoenixTemplateServer.Vault.encrypt!(raw_api_key)

      {:ok, api_key} =
        AlveraPhoenixTemplateServer.ApiKeyContext.create_api_key(platform_session, %{
          name: "Test API Key",
          key_hash: key_hash,
          key_value: encrypted_key,
          role_id: tenant_admin_role.id,
          tenant_id: platform_tenant.id
        })

      session =
        build(:session,
          type: :api,
          api_key_id: api_key.id,
          role_id: tenant_admin_role.id,
          tenant_id: platform_tenant.id
        )
        |> AlveraPhoenixTemplateServer.Repo.insert!(skip_multi_tenancy_check: true)

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-api-key", raw_api_key)
        |> assign(:api_session, session)
        |> put(~p"/api/tenants/#{tenant.id}", @update_attrs)

      assert json_response(conn, 403)
    end
  end

  describe "delete (DELETE /api/tenants/:id)" do
    setup [:create_tenant]

    test "deletes chosen tenant", %{conn: conn, tenant: tenant, plain_api_key: plain_api_key} do
      delete_conn = delete(conn, ~p"/api/tenants/#{tenant.id}")
      assert response(delete_conn, 204)

      # Verify tenant was deleted via GET request
      get_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> get(~p"/api/tenants/#{tenant.id}")

      assert json_response(get_conn, 404)
    end

    test "renders 404 when tenant does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()

      conn = delete(conn, ~p"/api/tenants/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "cannot delete tenant twice", %{conn: conn, tenant: tenant, plain_api_key: plain_api_key} do
      # First deletion succeeds
      conn = delete(conn, ~p"/api/tenants/#{tenant.id}")
      assert response(conn, 204)

      # Second deletion fails with 404
      conn2 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> delete(~p"/api/tenants/#{tenant.id}")

      assert json_response(conn2, 404)
    end

    test "returns 401 without API key", %{tenant: tenant} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> delete(~p"/api/tenants/#{tenant.id}")

      assert json_response(conn, 401)
    end

    test "returns 403 with non-platform_admin_api role", %{
      platform_tenant: platform_tenant,
      session: platform_session,
      tenant: tenant
    } do
      # Create a different role (not platform_admin_api)
      tenant_admin_role =
        build(:role,
          name: "tenant_admin",
          tenant_id: platform_tenant.id
        )
        |> AlveraPhoenixTemplateServer.Repo.insert!(skip_multi_tenancy_check: true)

      # Generate API key with proper encryption through context
      raw_api_key = "test_api_key_#{:crypto.strong_rand_bytes(16) |> Base.encode64()}"
      key_hash = :crypto.hash(:sha256, raw_api_key) |> Base.encode16(case: :lower)
      encrypted_key = AlveraPhoenixTemplateServer.Vault.encrypt!(raw_api_key)

      {:ok, api_key} =
        AlveraPhoenixTemplateServer.ApiKeyContext.create_api_key(platform_session, %{
          name: "Test API Key",
          key_hash: key_hash,
          key_value: encrypted_key,
          role_id: tenant_admin_role.id,
          tenant_id: platform_tenant.id
        })

      session =
        build(:session,
          type: :api,
          api_key_id: api_key.id,
          role_id: tenant_admin_role.id,
          tenant_id: platform_tenant.id
        )
        |> AlveraPhoenixTemplateServer.Repo.insert!(skip_multi_tenancy_check: true)

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", raw_api_key)
        |> assign(:api_session, session)
        |> delete(~p"/api/tenants/#{tenant.id}")

      assert json_response(conn, 403)
    end
  end

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes tenant endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "openapi" => "3.1.0",
               "paths" => paths
             } = response

      # Verify tenant endpoints are documented
      assert paths["/api/tenants"]
      assert paths["/api/tenants"]["get"]
      assert paths["/api/tenants"]["post"]
      assert paths["/api/tenants/{id}"]
      assert paths["/api/tenants/{id}"]["get"]
      assert paths["/api/tenants/{id}"]["put"]
      assert paths["/api/tenants/{id}"]["delete"]
    end

    test "OpenAPI spec includes tenant schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{
                 "schemas" => schemas
               }
             } = response

      # Verify tenant schemas exist
      assert schemas["TenantRequest"]
      assert schemas["TenantResponse"]
      assert schemas["TenantListResponse"]
    end

    test "TenantRequest schema has required fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{
                 "schemas" => %{
                   "TenantRequest" => request_schema
                 }
               }
             } = response

      # Verify required fields
      assert "name" in request_schema["required"]
      assert "tenant_type" in request_schema["required"]

      # Verify properties exist
      assert request_schema["properties"]["name"]
      assert request_schema["properties"]["tenant_type"]
      assert request_schema["properties"]["slug"]
      assert request_schema["properties"]["status"]
      assert request_schema["properties"]["metadata"]
    end

    test "TenantResponse schema includes all fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{
                 "schemas" => %{
                   "TenantResponse" => response_schema
                 }
               }
             } = response

      # Verify response schema includes read-only fields
      assert response_schema["properties"]["id"]
      assert response_schema["properties"]["name"]
      assert response_schema["properties"]["slug"]
      assert response_schema["properties"]["status"]
      assert response_schema["properties"]["tenant_type"]
      assert response_schema["properties"]["metadata"]
      assert response_schema["properties"]["inserted_at"]
      assert response_schema["properties"]["updated_at"]
    end
  end

  describe "content negotiation" do
    test "requires JSON accept header for list", %{conn: conn} do
      # Phoenix raises NotAcceptableError when accept header doesn't match
      assert_raise Phoenix.NotAcceptableError, fn ->
        conn
        |> Plug.Conn.delete_req_header("accept")
        |> put_req_header("accept", "text/html")
        |> get(~p"/api/tenants")
      end
    end

    test "requires JSON content-type for create", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.delete_req_header("content-type")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post(~p"/api/tenants", %{"tenant" => @create_attrs})

      # OpenApiSpex validates content-type and rejects non-JSON
      assert conn.status == 422
    end
  end

  defp create_tenant(_context) do
    tenant = insert(:tenant, tenant_type: :standard, name: "Test Tenant for Update/Delete")
    %{tenant: tenant}
  end
end
