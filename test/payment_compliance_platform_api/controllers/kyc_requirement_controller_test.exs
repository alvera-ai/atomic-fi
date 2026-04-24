defmodule PaymentCompliancePlatformApi.KycRequirementControllerTest do
  use PaymentCompliancePlatformWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import PaymentCompliancePlatform.Factory

  alias PaymentCompliancePlatformApi.ApiSpec

  @base_attrs %{
    scope: "account_holder",
    requirement_type: "identity_document",
    status: "pending"
  }

  @update_attrs %{
    scope: "account_holder",
    requirement_type: "identity_document",
    status: "approved"
  }

  @invalid_attrs %{scope: nil, requirement_type: nil}

  defp create_attrs(tenant_id, account_holder_id, legal_entity_id) do
    @base_attrs
    |> Map.put(:tenant_id, tenant_id)
    |> Map.put(:account_holder_id, account_holder_id)
    |> Map.put(:legal_entity_id, legal_entity_id)
  end

  defp update_attrs(tenant_id, account_holder_id, legal_entity_id) do
    @update_attrs
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

  describe "index (GET /api/kyc-requirements)" do
    test "lists kyc requirements for tenant", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      _req1 =
        insert(:kyc_requirement,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id,
          legal_entity_id: legal_entity.id,
          scope: :account_holder,
          requirement_type: :identity_document
        )

      legal_entity2 = insert(:legal_entity, tenant_id: platform_tenant.id)

      _req2 =
        insert(:kyc_requirement,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id,
          legal_entity_id: legal_entity2.id,
          scope: :account_holder,
          requirement_type: :proof_of_address
        )

      conn = get(conn, ~p"/api/kyc-requirements")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "KycRequirementListResponse", api_spec)

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
      requirement_types = [
        :identity_document,
        :proof_of_address,
        :source_of_funds,
        :business_relationship,
        :pep_declaration
      ]

      for rt <- requirement_types do
        le = insert(:legal_entity, tenant_id: platform_tenant.id)

        insert(:kyc_requirement,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id,
          legal_entity_id: le.id,
          scope: :account_holder,
          requirement_type: rt
        )
      end

      conn = get(conn, ~p"/api/kyc-requirements", %{"page" => 1, "page_size" => 3})
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "KycRequirementListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert length(data) == 3
      assert meta["page"] == 1
      assert meta["page_size"] == 3
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/kyc-requirements")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/kyc-requirements/:id)" do
    setup [:create_kyc_requirement]

    test "renders kyc requirement", %{conn: conn, kyc_requirement: kyc_requirement} do
      conn = get(conn, ~p"/api/kyc-requirements/#{kyc_requirement.id}")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "KycRequirementResponse", api_spec)

      assert %{
               "id" => id,
               "scope" => "account_holder",
               "requirement_type" => "identity_document",
               "status" => "pending"
             } = response

      assert id == kyc_requirement.id
    end

    test "renders 404 when kyc requirement does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/kyc-requirements/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "renders 422 when id is invalid format", %{conn: conn} do
      conn = get(conn, ~p"/api/kyc-requirements/invalid-uuid")
      assert conn.status == 422
    end

    test "returns 401 without API key", %{kyc_requirement: kyc_requirement} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/kyc-requirements/#{kyc_requirement.id}")

      assert json_response(conn, 401)
    end
  end

  describe "create (POST /api/kyc-requirements)" do
    test "creates kyc requirement", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      conn =
        post(
          conn,
          ~p"/api/kyc-requirements",
          create_attrs(platform_tenant.id, account_holder.id, legal_entity.id)
        )

      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "KycRequirementResponse", api_spec)

      assert %{
               "id" => id,
               "scope" => "account_holder",
               "requirement_type" => "identity_document",
               "status" => "pending",
               "account_holder_id" => account_holder_id,
               "legal_entity_id" => legal_entity_id
             } = response

      assert is_binary(id)
      assert account_holder_id == account_holder.id
      assert legal_entity_id == legal_entity.id
      assert Plug.Conn.get_resp_header(conn, "location") == ["/api/kyc-requirements/#{id}"]
    end

    test "creates kyc requirement with optional fields", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      attrs =
        create_attrs(platform_tenant.id, account_holder.id, legal_entity.id)
        |> Map.merge(%{
          kyc_requirement_number: "KYC-2026-001",
          deadline: "2026-12-31",
          scope: "beneficial_owner",
          requirement_type: "ubo_declaration"
        })

      conn = post(conn, ~p"/api/kyc-requirements", attrs)
      response = json_response(conn, 201)

      assert %{
               "kyc_requirement_number" => "KYC-2026-001",
               "deadline" => "2026-12-31",
               "scope" => "beneficial_owner",
               "requirement_type" => "ubo_declaration"
             } = response
    end

    test "renders errors when scope is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/kyc-requirements", @invalid_attrs)
      response = json_response(conn, 422)
      assert %{"errors" => errors} = response
      assert is_list(errors)
      assert errors != []
    end

    test "renders errors when scope is invalid enum", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      attrs =
        create_attrs(platform_tenant.id, account_holder.id, legal_entity.id)
        |> Map.put(:scope, "invalid_scope")

      conn = post(conn, ~p"/api/kyc-requirements", attrs)
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
          ~p"/api/kyc-requirements",
          @base_attrs
          |> Map.put(:account_holder_id, account_holder.id)
          |> Map.put(:legal_entity_id, legal_entity.id)
        )

      assert json_response(conn, 401)
    end
  end

  describe "update (PUT /api/kyc-requirements/:id)" do
    setup [:create_kyc_requirement]

    test "updates kyc requirement with valid data", %{
      conn: conn,
      kyc_requirement: kyc_requirement,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      conn =
        put(
          conn,
          ~p"/api/kyc-requirements/#{kyc_requirement.id}",
          update_attrs(platform_tenant.id, account_holder.id, legal_entity.id)
        )

      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "KycRequirementResponse", api_spec)

      assert %{
               "id" => id,
               "status" => "approved"
             } = response

      assert id == kyc_requirement.id
    end

    test "renders errors when data is invalid", %{conn: conn, kyc_requirement: kyc_requirement} do
      conn = put(conn, ~p"/api/kyc-requirements/#{kyc_requirement.id}", @invalid_attrs)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert is_list(errors)
      assert errors != []
    end

    test "renders 404 when kyc requirement does not exist", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      non_existent_id = Ecto.UUID.generate()

      conn =
        put(
          conn,
          ~p"/api/kyc-requirements/#{non_existent_id}",
          update_attrs(platform_tenant.id, account_holder.id, legal_entity.id)
        )

      assert json_response(conn, 404)
    end

    test "returns 401 without API key", %{
      kyc_requirement: kyc_requirement,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put(
          ~p"/api/kyc-requirements/#{kyc_requirement.id}",
          @update_attrs
          |> Map.put(:account_holder_id, account_holder.id)
          |> Map.put(:legal_entity_id, legal_entity.id)
        )

      assert json_response(conn, 401)
    end
  end

  describe "delete (DELETE /api/kyc-requirements/:id)" do
    setup [:create_kyc_requirement]

    test "deletes kyc requirement", %{
      conn: conn,
      kyc_requirement: kyc_requirement,
      plain_api_key: plain_api_key
    } do
      delete_conn = delete(conn, ~p"/api/kyc-requirements/#{kyc_requirement.id}")
      assert response(delete_conn, 204)

      get_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> get(~p"/api/kyc-requirements/#{kyc_requirement.id}")

      assert json_response(get_conn, 404)
    end

    test "renders 404 when kyc requirement does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = delete(conn, ~p"/api/kyc-requirements/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "cannot delete kyc requirement twice", %{
      conn: conn,
      kyc_requirement: kyc_requirement,
      plain_api_key: plain_api_key
    } do
      conn = delete(conn, ~p"/api/kyc-requirements/#{kyc_requirement.id}")
      assert response(conn, 204)

      conn2 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> delete(~p"/api/kyc-requirements/#{kyc_requirement.id}")

      assert json_response(conn2, 404)
    end

    test "returns 401 without API key", %{kyc_requirement: kyc_requirement} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> delete(~p"/api/kyc-requirements/#{kyc_requirement.id}")

      assert json_response(conn, 401)
    end
  end

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes kyc requirement endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"openapi" => "3.1.0", "paths" => paths} = response

      assert paths["/api/kyc-requirements"]
      assert paths["/api/kyc-requirements"]["get"]
      assert paths["/api/kyc-requirements"]["post"]
      assert paths["/api/kyc-requirements/{id}"]
      assert paths["/api/kyc-requirements/{id}"]["get"]
      assert paths["/api/kyc-requirements/{id}"]["put"]
      assert paths["/api/kyc-requirements/{id}"]["delete"]
    end

    test "OpenAPI spec includes KycRequirement schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => schemas}} = response

      assert schemas["KycRequirementRequest"]
      assert schemas["KycRequirementResponse"]
      assert schemas["KycRequirementListResponse"]
    end

    test "KycRequirementRequest excludes server-generated readOnly fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{"schemas" => %{"KycRequirementRequest" => request_schema}}
             } = response

      refute get_in(request_schema, ["properties", "id"])
      refute get_in(request_schema, ["properties", "inserted_at"])
      refute get_in(request_schema, ["properties", "updated_at"])

      assert get_in(request_schema, ["properties", "scope"])
      assert get_in(request_schema, ["properties", "requirement_type"])
      assert get_in(request_schema, ["properties", "account_holder_id"])
      assert get_in(request_schema, ["properties", "legal_entity_id"])
    end

    test "KycRequirementResponse includes all fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{"schemas" => %{"KycRequirementResponse" => response_schema}}
             } = response

      assert get_in(response_schema, ["properties", "id"])
      assert get_in(response_schema, ["properties", "scope"])
      assert get_in(response_schema, ["properties", "requirement_type"])
      assert get_in(response_schema, ["properties", "status"])
      assert get_in(response_schema, ["properties", "account_holder_id"])
      assert get_in(response_schema, ["properties", "legal_entity_id"])
      assert get_in(response_schema, ["properties", "inserted_at"])
      assert get_in(response_schema, ["properties", "updated_at"])
    end
  end

  defp create_kyc_requirement(%{
         platform_tenant: platform_tenant,
         account_holder: account_holder,
         legal_entity: legal_entity
       }) do
    kyc_requirement =
      insert(:kyc_requirement,
        tenant_id: platform_tenant.id,
        account_holder_id: account_holder.id,
        legal_entity_id: legal_entity.id,
        scope: :account_holder,
        requirement_type: :identity_document
      )

    %{kyc_requirement: kyc_requirement}
  end
end
