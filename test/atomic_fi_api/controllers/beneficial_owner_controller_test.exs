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

  defp nested_le(tenant_id) do
    %{
      legal_entity_type: "individual",
      first_name: "BO",
      last_name: "Holder",
      citizenship_country: "US",
      politically_exposed_person: false,
      tenant_id: tenant_id
    }
  end

  defp create_attrs(tenant_id, account_holder_id) do
    @individual_attrs
    |> Map.put(:tenant_id, tenant_id)
    |> Map.put(:account_holder_id, account_holder_id)
    |> Map.put(:legal_entity, nested_le(tenant_id))
  end

  defp update_attrs(tenant_id, account_holder_id) do
    @update_fields
    |> Map.put(:tenant_id, tenant_id)
    |> Map.put(:account_holder_id, account_holder_id)
  end

  setup :setup_platform_admin_api

  setup %{platform_tenant: platform_tenant} do
    account_holder = insert(:account_holder, tenant_id: platform_tenant.id)
    %{account_holder: account_holder}
  end

  describe "index (GET /api/beneficial-owners)" do
    test "lists beneficial owners for tenant", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      _bo1 =
        insert(:beneficial_owner,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id
        )

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
      account_holder: account_holder
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
      account_holder: account_holder
    } do
      conn =
        post(
          conn,
          ~p"/api/beneficial-owners",
          create_attrs(platform_tenant.id, account_holder.id)
        )

      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "BeneficialOwnerResponse", api_spec)

      assert %{
               "id" => id,
               "control_type" => "shareholder",
               "verification_status" => "pending",
               "account_holder_id" => account_holder_id,
               "legal_entity" => %{"id" => le_id}
             } = response

      assert is_binary(id)
      assert account_holder_id == account_holder.id
      assert is_binary(le_id)
      assert Plug.Conn.get_resp_header(conn, "location") == ["/api/beneficial-owners/#{id}"]
    end

    test "creates beneficial owner with optional fields", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      attrs =
        create_attrs(platform_tenant.id, account_holder.id)
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
      account_holder: account_holder
    } do
      attrs =
        create_attrs(platform_tenant.id, account_holder.id)
        |> Map.put(:control_type, "invalid_type")

      conn = post(conn, ~p"/api/beneficial-owners", attrs)
      assert json_response(conn, 422)
    end

    test "returns 401 without API key", %{
      account_holder: account_holder,
      platform_tenant: platform_tenant
    } do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/beneficial-owners",
          create_attrs(platform_tenant.id, account_holder.id)
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
      account_holder: account_holder
    } do
      conn =
        put(
          conn,
          ~p"/api/beneficial-owners/#{beneficial_owner.id}",
          update_attrs(platform_tenant.id, account_holder.id)
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
      account_holder: account_holder
    } do
      non_existent_id = Ecto.UUID.generate()

      conn =
        put(
          conn,
          ~p"/api/beneficial-owners/#{non_existent_id}",
          update_attrs(platform_tenant.id, account_holder.id)
        )

      assert json_response(conn, 404)
    end

    test "returns 401 without API key", %{
      beneficial_owner: beneficial_owner,
      account_holder: account_holder
    } do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put(
          ~p"/api/beneficial-owners/#{beneficial_owner.id}",
          @update_fields
          |> Map.put(:account_holder_id, account_holder.id)
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

  describe "update_legal_entity (PUT /api/beneficial-owners/:id/legal-entity)" do
    setup [:create_beneficial_owner]

    test "replaces the linked LE PII", %{
      conn: conn,
      beneficial_owner: beneficial_owner,
      platform_tenant: platform_tenant
    } do
      body = %{
        legal_entity_type: "individual",
        first_name: "BO",
        last_name: "Updated",
        citizenship_country: "GB",
        tenant_id: platform_tenant.id
      }

      conn = put(conn, ~p"/api/beneficial-owners/#{beneficial_owner.id}/legal-entity", body)
      response = json_response(conn, 200)

      assert_schema(response, "LegalEntityResponse", ApiSpec.spec())
      assert response["first_name"] == "BO"
      assert response["citizenship_country"] == "GB"
    end

    test "renders 404 when beneficial owner does not exist", %{
      conn: conn,
      platform_tenant: platform_tenant
    } do
      body = %{legal_entity_type: "individual", first_name: "X", tenant_id: platform_tenant.id}

      conn =
        put(conn, ~p"/api/beneficial-owners/#{Ecto.UUID.generate()}/legal-entity", body)

      assert json_response(conn, 404)
    end

    test "returns 401 without API key", %{
      beneficial_owner: beneficial_owner,
      platform_tenant: platform_tenant
    } do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put(
          ~p"/api/beneficial-owners/#{beneficial_owner.id}/legal-entity",
          %{legal_entity_type: "individual", first_name: "X", tenant_id: platform_tenant.id}
        )

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

      refute get_in(request_schema, ["properties", "id"])
      refute get_in(request_schema, ["properties", "inserted_at"])
      refute get_in(request_schema, ["properties", "updated_at"])

      assert get_in(request_schema, ["properties", "account_holder_id"])
      assert get_in(request_schema, ["properties", "legal_entity"])
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
      assert get_in(response_schema, ["properties", "control_type"])
      assert get_in(response_schema, ["properties", "inserted_at"])
      assert get_in(response_schema, ["properties", "updated_at"])
    end
  end

  defp create_beneficial_owner(%{
         platform_tenant: platform_tenant,
         account_holder: account_holder
       }) do
    beneficial_owner =
      insert(:beneficial_owner,
        tenant_id: platform_tenant.id,
        account_holder_id: account_holder.id
      )

    insert(:legal_entity,
      beneficial_owner_id: beneficial_owner.id,
      subject_type: :beneficial_owner,
      account_holder_id: account_holder.id,
      tenant_id: platform_tenant.id
    )

    %{beneficial_owner: beneficial_owner}
  end
end
