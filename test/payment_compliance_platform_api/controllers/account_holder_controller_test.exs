defmodule PaymentCompliancePlatformApi.AccountHolderControllerTest do
  use PaymentCompliancePlatformWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import PaymentCompliancePlatform.Factory

  alias PaymentCompliancePlatformApi.ApiSpec

  @individual_attrs %{
    holder_type: "individual",
    status: "pending",
    kyc_status: "not_started",
    risk_level: "low",
    enabled_currencies: ["USD"]
  }

  @update_fields %{
    holder_type: "business",
    status: "active",
    kyc_status: "approved",
    risk_level: "medium",
    enabled_currencies: ["USD", "EUR"]
  }

  @invalid_attrs %{
    holder_type: nil
  }

  defp create_attrs(tenant_id, legal_entity_id) do
    @individual_attrs
    |> Map.put(:tenant_id, tenant_id)
    |> Map.put(:legal_entity_id, legal_entity_id)
  end

  defp update_attrs(tenant_id, legal_entity_id) do
    @update_fields
    |> Map.put(:tenant_id, tenant_id)
    |> Map.put(:legal_entity_id, legal_entity_id)
  end

  setup :setup_platform_admin_api

  setup %{platform_tenant: platform_tenant} do
    legal_entity = insert(:legal_entity, tenant_id: platform_tenant.id)
    %{legal_entity: legal_entity}
  end

  describe "index (GET /api/account-holders)" do
    test "lists account holders for tenant", %{
      conn: conn,
      platform_tenant: platform_tenant,
      legal_entity: legal_entity
    } do
      _ah1 =
        insert(:account_holder,
          tenant_id: platform_tenant.id,
          legal_entity_id: legal_entity.id
        )

      _ah2 =
        insert(:account_holder,
          tenant_id: platform_tenant.id,
          legal_entity_id: legal_entity.id
        )

      conn = get(conn, ~p"/api/account-holders")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "AccountHolderListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert is_list(data)
      assert length(data) >= 2
      assert meta["total_count"] >= 2
    end

    test "supports pagination", %{
      conn: conn,
      platform_tenant: platform_tenant,
      legal_entity: legal_entity
    } do
      for _ <- 1..12 do
        insert(:account_holder,
          tenant_id: platform_tenant.id,
          legal_entity_id: legal_entity.id
        )
      end

      conn = get(conn, ~p"/api/account-holders", %{"page" => 1, "page_size" => 5})
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "AccountHolderListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert length(data) == 5
      assert meta["page"] == 1
      assert meta["page_size"] == 5
    end

    test "supports sorting by inserted_at descending", %{
      conn: conn,
      platform_tenant: platform_tenant,
      legal_entity: legal_entity
    } do
      _older =
        insert(:account_holder,
          tenant_id: platform_tenant.id,
          legal_entity_id: legal_entity.id
        )

      _newer =
        insert(:account_holder,
          tenant_id: platform_tenant.id,
          legal_entity_id: legal_entity.id
        )

      conn =
        get(conn, ~p"/api/account-holders", %{
          "order_by" => "inserted_at",
          "order_directions" => "desc"
        })

      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "AccountHolderListResponse", api_spec)
      assert %{"data" => data} = response
      assert is_list(data)
    end

    test "includes own tenant account holders in results", %{
      conn: conn,
      platform_tenant: platform_tenant,
      legal_entity: legal_entity
    } do
      ah =
        insert(:account_holder,
          tenant_id: platform_tenant.id,
          legal_entity_id: legal_entity.id
        )

      conn = get(conn, ~p"/api/account-holders")
      response = json_response(conn, 200)

      assert %{"data" => data} = response
      ids = Enum.map(data, & &1["id"])
      assert ah.id in ids
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/account-holders")

      assert json_response(conn, 401)
    end

    test "returns 401 with invalid API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", "invalid_key")
        |> get(~p"/api/account-holders")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/account-holders/:id)" do
    setup [:create_account_holder]

    test "renders account holder", %{conn: conn, account_holder: account_holder} do
      conn = get(conn, ~p"/api/account-holders/#{account_holder.id}")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "AccountHolderResponse", api_spec)

      assert %{
               "id" => id,
               "holder_type" => "individual",
               "status" => "pending",
               "kyc_status" => "not_started",
               "risk_level" => "low"
             } = response

      assert id == account_holder.id
    end

    test "renders 404 when account holder does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/account-holders/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "renders 422 when id is invalid format", %{conn: conn} do
      conn = get(conn, ~p"/api/account-holders/invalid-uuid")
      assert conn.status == 422
    end

    test "returns 401 without API key", %{account_holder: account_holder} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/account-holders/#{account_holder.id}")

      assert json_response(conn, 401)
    end
  end

  describe "create (POST /api/account-holders)" do
    test "creates individual account holder", %{
      conn: conn,
      platform_tenant: platform_tenant,
      legal_entity: legal_entity
    } do
      conn =
        post(conn, ~p"/api/account-holders", create_attrs(platform_tenant.id, legal_entity.id))

      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "AccountHolderResponse", api_spec)

      assert %{
               "id" => id,
               "holder_type" => "individual",
               "status" => "pending",
               "kyc_status" => "not_started",
               "legal_entity_id" => legal_entity_id
             } = response

      assert is_binary(id)
      assert legal_entity_id == legal_entity.id
      assert Plug.Conn.get_resp_header(conn, "location") == ["/api/account-holders/#{id}"]
    end

    test "creates account holder with optional fields", %{
      conn: conn,
      platform_tenant: platform_tenant,
      legal_entity: legal_entity
    } do
      attrs =
        create_attrs(platform_tenant.id, legal_entity.id)
        |> Map.merge(%{
          account_holder_number: "AH-001",
          external_id: "ext-123",
          enabled_currencies: ["USD", "EUR"]
        })

      conn = post(conn, ~p"/api/account-holders", attrs)
      response = json_response(conn, 201)

      assert %{
               "account_holder_number" => "AH-001",
               "external_id" => "ext-123",
               "enabled_currencies" => ["USD", "EUR"]
             } = response
    end

    test "renders errors when holder_type is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/account-holders", @invalid_attrs)
      response = json_response(conn, 422)
      assert %{"errors" => errors} = response
      assert is_list(errors)
      assert errors != []
    end

    test "renders errors when holder_type is invalid enum", %{
      conn: conn,
      platform_tenant: platform_tenant,
      legal_entity: legal_entity
    } do
      attrs =
        create_attrs(platform_tenant.id, legal_entity.id)
        |> Map.put(:holder_type, "invalid_type")

      conn = post(conn, ~p"/api/account-holders", attrs)
      assert json_response(conn, 422)
    end

    test "returns 401 without API key", %{legal_entity: legal_entity} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/account-holders",
          Map.put(@individual_attrs, :legal_entity_id, legal_entity.id)
        )

      assert json_response(conn, 401)
    end
  end

  describe "update (PUT /api/account-holders/:id)" do
    setup [:create_account_holder]

    test "updates account holder with valid data", %{
      conn: conn,
      account_holder: account_holder,
      platform_tenant: platform_tenant,
      legal_entity: legal_entity
    } do
      conn =
        put(
          conn,
          ~p"/api/account-holders/#{account_holder.id}",
          update_attrs(platform_tenant.id, legal_entity.id)
        )

      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "AccountHolderResponse", api_spec)

      assert %{
               "id" => id,
               "holder_type" => "business",
               "status" => "active",
               "kyc_status" => "approved",
               "risk_level" => "medium"
             } = response

      assert id == account_holder.id
    end

    test "renders errors when data is invalid", %{conn: conn, account_holder: account_holder} do
      conn = put(conn, ~p"/api/account-holders/#{account_holder.id}", @invalid_attrs)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert is_list(errors)
      assert errors != []
    end

    test "renders 404 when account holder does not exist", %{
      conn: conn,
      platform_tenant: platform_tenant,
      legal_entity: legal_entity
    } do
      non_existent_id = Ecto.UUID.generate()

      conn =
        put(
          conn,
          ~p"/api/account-holders/#{non_existent_id}",
          update_attrs(platform_tenant.id, legal_entity.id)
        )

      assert json_response(conn, 404)
    end

    test "returns 401 without API key", %{
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put(
          ~p"/api/account-holders/#{account_holder.id}",
          Map.put(@update_fields, :legal_entity_id, legal_entity.id)
        )

      assert json_response(conn, 401)
    end
  end

  describe "delete (DELETE /api/account-holders/:id)" do
    setup [:create_account_holder]

    test "deletes account holder", %{
      conn: conn,
      account_holder: account_holder,
      plain_api_key: plain_api_key
    } do
      delete_conn = delete(conn, ~p"/api/account-holders/#{account_holder.id}")
      assert response(delete_conn, 204)

      # Verify deleted via GET
      get_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> get(~p"/api/account-holders/#{account_holder.id}")

      assert json_response(get_conn, 404)
    end

    test "renders 404 when account holder does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = delete(conn, ~p"/api/account-holders/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "cannot delete account holder twice", %{
      conn: conn,
      account_holder: account_holder,
      plain_api_key: plain_api_key
    } do
      conn = delete(conn, ~p"/api/account-holders/#{account_holder.id}")
      assert response(conn, 204)

      conn2 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> delete(~p"/api/account-holders/#{account_holder.id}")

      assert json_response(conn2, 404)
    end

    test "returns 401 without API key", %{account_holder: account_holder} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> delete(~p"/api/account-holders/#{account_holder.id}")

      assert json_response(conn, 401)
    end
  end

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes account holder endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"openapi" => "3.1.0", "paths" => paths} = response

      assert paths["/api/account-holders"]
      assert paths["/api/account-holders"]["get"]
      assert paths["/api/account-holders"]["post"]
      assert paths["/api/account-holders/{id}"]
      assert paths["/api/account-holders/{id}"]["get"]
      assert paths["/api/account-holders/{id}"]["put"]
      assert paths["/api/account-holders/{id}"]["delete"]
    end

    test "OpenAPI spec includes AccountHolder schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => schemas}} = response

      assert schemas["AccountHolderRequest"]
      assert schemas["AccountHolderResponse"]
      assert schemas["AccountHolderListResponse"]
    end

    test "AccountHolderRequest excludes server-generated readOnly fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{"schemas" => %{"AccountHolderRequest" => request_schema}}
             } = response

      # Server-generated readOnly fields should not appear in Request schema
      refute get_in(request_schema, ["properties", "id"])
      refute get_in(request_schema, ["properties", "inserted_at"])
      refute get_in(request_schema, ["properties", "updated_at"])

      # Writable fields should be present
      assert get_in(request_schema, ["properties", "legal_entity_id"])
      assert get_in(request_schema, ["properties", "holder_type"])
      assert get_in(request_schema, ["properties", "status"])
      assert get_in(request_schema, ["properties", "tenant_id"])
    end

    test "AccountHolderResponse includes all fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{"schemas" => %{"AccountHolderResponse" => response_schema}}
             } = response

      assert get_in(response_schema, ["properties", "id"])
      assert get_in(response_schema, ["properties", "legal_entity_id"])
      assert get_in(response_schema, ["properties", "holder_type"])
      assert get_in(response_schema, ["properties", "status"])
      assert get_in(response_schema, ["properties", "inserted_at"])
      assert get_in(response_schema, ["properties", "updated_at"])
    end
  end

  defp create_account_holder(%{platform_tenant: platform_tenant, legal_entity: legal_entity}) do
    account_holder =
      insert(:account_holder,
        tenant_id: platform_tenant.id,
        legal_entity_id: legal_entity.id
      )

    %{account_holder: account_holder}
  end
end
