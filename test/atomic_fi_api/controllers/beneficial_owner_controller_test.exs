defmodule AtomicFiApi.BeneficialOwnerControllerTest do
  use AtomicFiWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import AtomicFi.Factory

  alias AtomicFiApi.ApiSpec

  @individual_attrs %{
    control_type: "shareholder",
    ownership_pct: 25.0,
    verification_status: "pending"
  }

  @update_fields %{
    control_type: "director",
    ownership_pct: 51.0,
    verification_status: "verified"
  }

  @invalid_attrs %{control_type: nil}

  defp create_attrs(tenant_id, account_holder_id, legal_entity_id) do
    @individual_attrs
    |> Map.put(:tenant_id, tenant_id)
    |> Map.put(:account_holder_id, account_holder_id)
    |> Map.put(:legal_entity_id, legal_entity_id)
  end

  defp update_attrs(tenant_id, account_holder_id, legal_entity_id) do
    @update_fields
    |> Map.put(:tenant_id, tenant_id)
    |> Map.put(:account_holder_id, account_holder_id)
    |> Map.put(:legal_entity_id, legal_entity_id)
  end

  setup :setup_platform_admin_api

  setup %{platform_tenant: platform_tenant} do
    account_holder = insert(:account_holder, tenant_id: platform_tenant.id)
    legal_entity = insert(:legal_entity, tenant_id: platform_tenant.id)
    %{account_holder: account_holder, legal_entity: legal_entity}
  end

  describe "index (GET /api/beneficial-owners)" do
    test "lists beneficial owners for tenant", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      _bo1 =
        insert(:beneficial_owner,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id
        )

      # Second with a different legal_entity to avoid unique constraint
      legal_entity2 = insert(:legal_entity, tenant_id: platform_tenant.id)

      _bo2 =
        insert(:beneficial_owner,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id
        )

      conn = get(conn, ~p"/api/beneficial-owners")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "BeneficialOwnerListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert is_list(data)
      assert length(data) >= 2
      assert meta["total_count"] >= 2
    end

    test "supports pagination", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      for _ <- 1..12 do
        le = insert(:legal_entity, tenant_id: platform_tenant.id)

        insert(:beneficial_owner,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id
        )
      end

      conn = get(conn, ~p"/api/beneficial-owners", %{"page" => 1, "page_size" => 5})
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "BeneficialOwnerListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert length(data) == 5
      assert meta["page"] == 1
      assert meta["page_size"] == 5
    end

    test "includes own tenant beneficial owners in results", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      bo =
        insert(:beneficial_owner,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id
        )

      conn = get(conn, ~p"/api/beneficial-owners")
      response = json_response(conn, 200)

      assert %{"data" => data} = response
      ids = Enum.map(data, & &1["id"])
      assert bo.id in ids
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/beneficial-owners")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/beneficial-owners/:id)" do
    setup [:create_beneficial_owner]

    test "renders beneficial owner", %{conn: conn, beneficial_owner: beneficial_owner} do
      conn = get(conn, ~p"/api/beneficial-owners/#{beneficial_owner.id}")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "BeneficialOwnerResponse", api_spec)

      assert %{
               "id" => id,
               "control_type" => "shareholder",
               "verification_status" => "pending",
               "ownership_pct" => 25.0
             } = response

      assert id == beneficial_owner.id
    end

    test "renders 404 when beneficial owner does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/beneficial-owners/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "renders 422 when id is invalid format", %{conn: conn} do
      conn = get(conn, ~p"/api/beneficial-owners/invalid-uuid")
      assert conn.status == 422
    end

    test "returns 401 without API key", %{beneficial_owner: beneficial_owner} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/beneficial-owners/#{beneficial_owner.id}")

      assert json_response(conn, 401)
    end
  end

  describe "create (POST /api/beneficial-owners)" do
    test "creates beneficial owner", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      conn =
        post(
          conn,
          ~p"/api/beneficial-owners",
          create_attrs(platform_tenant.id, account_holder.id, legal_entity.id)
        )

      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "BeneficialOwnerResponse", api_spec)

      assert %{
               "id" => id,
               "control_type" => "shareholder",
               "verification_status" => "pending",
               "account_holder_id" => account_holder_id,
               "legal_entity_id" => legal_entity_id
             } = response

      assert is_binary(id)
      assert account_holder_id == account_holder.id
      assert legal_entity_id == legal_entity.id
      assert Plug.Conn.get_resp_header(conn, "location") == ["/api/beneficial-owners/#{id}"]
    end

    test "creates beneficial owner with optional fields", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      attrs =
        create_attrs(platform_tenant.id, account_holder.id, legal_entity.id)
        |> Map.merge(%{
          beneficial_owner_number: "BO-001",
          ownership_pct: 51.0
        })

      conn = post(conn, ~p"/api/beneficial-owners", attrs)
      response = json_response(conn, 201)

      assert %{
               "beneficial_owner_number" => "BO-001",
               "ownership_pct" => 51.0
             } = response
    end

    test "renders errors when control_type is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/beneficial-owners", @invalid_attrs)
      response = json_response(conn, 422)
      assert %{"errors" => errors} = response
      assert is_list(errors)
      assert errors != []
    end

    test "renders errors when control_type is invalid enum", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      attrs =
        create_attrs(platform_tenant.id, account_holder.id, legal_entity.id)
        |> Map.put(:control_type, "invalid_type")

      conn = post(conn, ~p"/api/beneficial-owners", attrs)
      assert json_response(conn, 422)
    end

    test "returns 401 without API key", %{
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/beneficial-owners",
          @individual_attrs
          |> Map.put(:account_holder_id, account_holder.id)
          |> Map.put(:legal_entity_id, legal_entity.id)
        )

      assert json_response(conn, 401)
    end
  end

  describe "update (PUT /api/beneficial-owners/:id)" do
    setup [:create_beneficial_owner]

    test "updates beneficial owner with valid data", %{
      conn: conn,
      beneficial_owner: beneficial_owner,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      conn =
        put(
          conn,
          ~p"/api/beneficial-owners/#{beneficial_owner.id}",
          update_attrs(platform_tenant.id, account_holder.id, legal_entity.id)
        )

      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "BeneficialOwnerResponse", api_spec)

      assert %{
               "id" => id,
               "control_type" => "director",
               "verification_status" => "verified",
               "ownership_pct" => 51.0
             } = response

      assert id == beneficial_owner.id
    end

    test "renders errors when data is invalid", %{conn: conn, beneficial_owner: beneficial_owner} do
      conn = put(conn, ~p"/api/beneficial-owners/#{beneficial_owner.id}", @invalid_attrs)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert is_list(errors)
      assert errors != []
    end

    test "renders 404 when beneficial owner does not exist", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      non_existent_id = Ecto.UUID.generate()

      conn =
        put(
          conn,
          ~p"/api/beneficial-owners/#{non_existent_id}",
          update_attrs(platform_tenant.id, account_holder.id, legal_entity.id)
        )

      assert json_response(conn, 404)
    end

    test "returns 401 without API key", %{
      beneficial_owner: beneficial_owner,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put(
          ~p"/api/beneficial-owners/#{beneficial_owner.id}",
          @update_fields
          |> Map.put(:account_holder_id, account_holder.id)
          |> Map.put(:legal_entity_id, legal_entity.id)
        )

      assert json_response(conn, 401)
    end
  end

  describe "delete (DELETE /api/beneficial-owners/:id)" do
    setup [:create_beneficial_owner]

    test "deletes beneficial owner", %{
      conn: conn,
      beneficial_owner: beneficial_owner,
      plain_api_key: plain_api_key
    } do
      delete_conn = delete(conn, ~p"/api/beneficial-owners/#{beneficial_owner.id}")
      assert response(delete_conn, 204)

      # Verify deleted via GET
      get_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> get(~p"/api/beneficial-owners/#{beneficial_owner.id}")

      assert json_response(get_conn, 404)
    end

    test "renders 404 when beneficial owner does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = delete(conn, ~p"/api/beneficial-owners/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "cannot delete beneficial owner twice", %{
      conn: conn,
      beneficial_owner: beneficial_owner,
      plain_api_key: plain_api_key
    } do
      conn = delete(conn, ~p"/api/beneficial-owners/#{beneficial_owner.id}")
      assert response(conn, 204)

      conn2 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> delete(~p"/api/beneficial-owners/#{beneficial_owner.id}")

      assert json_response(conn2, 404)
    end

    test "returns 401 without API key", %{beneficial_owner: beneficial_owner} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> delete(~p"/api/beneficial-owners/#{beneficial_owner.id}")

      assert json_response(conn, 401)
    end
  end

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes beneficial owner endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"openapi" => "3.1.0", "paths" => paths} = response

      assert paths["/api/beneficial-owners"]
      assert paths["/api/beneficial-owners"]["get"]
      assert paths["/api/beneficial-owners"]["post"]
      assert paths["/api/beneficial-owners/{id}"]
      assert paths["/api/beneficial-owners/{id}"]["get"]
      assert paths["/api/beneficial-owners/{id}"]["put"]
      assert paths["/api/beneficial-owners/{id}"]["delete"]
    end

    test "OpenAPI spec includes BeneficialOwner schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => schemas}} = response

      assert schemas["BeneficialOwnerRequest"]
      assert schemas["BeneficialOwnerResponse"]
      assert schemas["BeneficialOwnerListResponse"]
    end

    test "BeneficialOwnerRequest excludes server-generated readOnly fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{"schemas" => %{"BeneficialOwnerRequest" => request_schema}}
             } = response

      # Server-generated readOnly fields should not appear in Request schema
      refute get_in(request_schema, ["properties", "id"])
      refute get_in(request_schema, ["properties", "inserted_at"])
      refute get_in(request_schema, ["properties", "updated_at"])

      # Writable fields should be present
      assert get_in(request_schema, ["properties", "account_holder_id"])
      assert get_in(request_schema, ["properties", "legal_entity_id"])
      assert get_in(request_schema, ["properties", "control_type"])
    end

    test "BeneficialOwnerResponse includes all fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{"schemas" => %{"BeneficialOwnerResponse" => response_schema}}
             } = response

      assert get_in(response_schema, ["properties", "id"])
      assert get_in(response_schema, ["properties", "account_holder_id"])
      assert get_in(response_schema, ["properties", "legal_entity_id"])
      assert get_in(response_schema, ["properties", "control_type"])
      assert get_in(response_schema, ["properties", "inserted_at"])
      assert get_in(response_schema, ["properties", "updated_at"])
    end
  end

  defp create_beneficial_owner(%{
         platform_tenant: platform_tenant,
         account_holder: account_holder,
         legal_entity: legal_entity
       }) do
    beneficial_owner =
      insert(:beneficial_owner,
        tenant_id: platform_tenant.id,
        account_holder_id: account_holder.id
      )

    %{beneficial_owner: beneficial_owner}
  end
end
