defmodule PaymentCompliancePlatformApi.LegalEntityControllerTest do
  use PaymentCompliancePlatformWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import PaymentCompliancePlatform.Factory

  alias PaymentCompliancePlatformApi.ApiSpec

  @individual_attrs %{
    legal_entity_type: "individual",
    first_name: "John",
    last_name: "Doe",
    date_of_birth: "1990-01-01",
    citizenship_country: "US",
    politically_exposed_person: false
  }

  @business_attrs %{
    legal_entity_type: "business",
    legal_structure: "llc",
    business_name: "Acme Corp",
    doing_business_as_names: ["Acme"],
    date_formed: "2020-01-01",
    website: "https://acme.example.com",
    citizenship_country: "US"
  }

  @update_fields %{
    legal_entity_type: "individual",
    first_name: "Jane",
    last_name: "Smith",
    citizenship_country: "CA",
    politically_exposed_person: true
  }

  @invalid_attrs %{
    legal_entity_type: nil
  }

  defp create_attrs(tenant_id), do: Map.put(@individual_attrs, :tenant_id, tenant_id)
  defp create_business_attrs(tenant_id), do: Map.put(@business_attrs, :tenant_id, tenant_id)
  defp update_attrs(tenant_id), do: Map.put(@update_fields, :tenant_id, tenant_id)

  setup :setup_platform_admin_api

  describe "index (GET /api/legal-entities)" do
    test "lists legal entities for tenant", %{conn: conn, platform_tenant: platform_tenant} do
      _entity1 = insert(:legal_entity, tenant_id: platform_tenant.id)
      _entity2 = insert(:legal_entity, tenant_id: platform_tenant.id)

      conn = get(conn, ~p"/api/legal-entities")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "LegalEntityListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert is_list(data)
      assert length(data) >= 2
      assert meta["total_count"] >= 2
    end

    test "supports pagination", %{conn: conn, platform_tenant: platform_tenant} do
      for _ <- 1..12, do: insert(:legal_entity, tenant_id: platform_tenant.id)

      conn = get(conn, ~p"/api/legal-entities", %{"page" => 1, "page_size" => 5})
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "LegalEntityListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert length(data) == 5
      assert meta["page"] == 1
      assert meta["page_size"] == 5
    end

    test "supports sorting by inserted_at descending", %{
      conn: conn,
      platform_tenant: platform_tenant
    } do
      _older = insert(:legal_entity, tenant_id: platform_tenant.id)
      _newer = insert(:legal_entity, tenant_id: platform_tenant.id)

      conn =
        get(conn, ~p"/api/legal-entities", %{
          "order_by" => "inserted_at",
          "order_directions" => "desc"
        })

      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "LegalEntityListResponse", api_spec)
      assert %{"data" => data} = response
      assert is_list(data)
    end

    test "includes own tenant entities in results", %{
      conn: conn,
      platform_tenant: platform_tenant
    } do
      my_entity = insert(:legal_entity, tenant_id: platform_tenant.id)

      conn = get(conn, ~p"/api/legal-entities")
      response = json_response(conn, 200)

      assert %{"data" => data} = response
      ids = Enum.map(data, & &1["id"])
      assert my_entity.id in ids
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/legal-entities")

      assert json_response(conn, 401)
    end

    test "returns 401 with invalid API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", "invalid_key")
        |> get(~p"/api/legal-entities")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/legal-entities/:id)" do
    setup [:create_legal_entity]

    test "renders legal entity with nested associations", %{
      conn: conn,
      legal_entity: legal_entity
    } do
      conn = get(conn, ~p"/api/legal-entities/#{legal_entity.id}")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "LegalEntityResponse", api_spec)

      assert %{
               "id" => id,
               "legal_entity_type" => "individual",
               "first_name" => _,
               "last_name" => _,
               "addresses" => addresses,
               "phone_numbers" => phone_numbers,
               "identifications" => identifications
             } = response

      assert id == legal_entity.id
      assert is_list(addresses)
      assert is_list(phone_numbers)
      assert is_list(identifications)
    end

    test "renders 404 when entity does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/legal-entities/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "renders 422 when id is invalid format", %{conn: conn} do
      conn = get(conn, ~p"/api/legal-entities/invalid-uuid")
      assert conn.status == 422
    end

    test "returns 401 without API key", %{legal_entity: legal_entity} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/legal-entities/#{legal_entity.id}")

      assert json_response(conn, 401)
    end
  end

  describe "create (POST /api/legal-entities)" do
    test "creates individual legal entity", %{conn: conn, platform_tenant: platform_tenant} do
      conn = post(conn, ~p"/api/legal-entities", create_attrs(platform_tenant.id))
      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "LegalEntityResponse", api_spec)

      assert %{
               "id" => id,
               "legal_entity_type" => "individual",
               "first_name" => "John",
               "last_name" => "Doe",
               "citizenship_country" => "US"
             } = response

      assert is_binary(id)
      assert Plug.Conn.get_resp_header(conn, "location") == ["/api/legal-entities/#{id}"]
    end

    test "creates business legal entity", %{conn: conn, platform_tenant: platform_tenant} do
      conn = post(conn, ~p"/api/legal-entities", create_business_attrs(platform_tenant.id))
      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "LegalEntityResponse", api_spec)

      assert %{
               "id" => _id,
               "legal_entity_type" => "business",
               "legal_structure" => "llc",
               "business_name" => "Acme Corp"
             } = response
    end

    test "creates legal entity with nested addresses", %{
      conn: conn,
      platform_tenant: platform_tenant
    } do
      attrs =
        create_attrs(platform_tenant.id)
        |> Map.put(:addresses, [
          %{
            address_types: ["residential"],
            primary: true,
            line1: "123 Main St",
            locality: "Springfield",
            region: "IL",
            postal_code: "62701",
            country: "US"
          }
        ])

      conn = post(conn, ~p"/api/legal-entities", attrs)
      response = json_response(conn, 201)

      assert %{"addresses" => [address]} = response
      assert address["line1"] == "123 Main St"
      assert address["country"] == "US"
    end

    test "creates legal entity with nested phone numbers", %{
      conn: conn,
      platform_tenant: platform_tenant
    } do
      attrs =
        create_attrs(platform_tenant.id)
        |> Map.put(:phone_numbers, [%{phone_number: "+12125551234"}])

      conn = post(conn, ~p"/api/legal-entities", attrs)
      response = json_response(conn, 201)

      assert %{"phone_numbers" => [phone]} = response
      assert phone["phone_number"] == "+12125551234"
    end

    test "creates legal entity with nested identifications", %{
      conn: conn,
      platform_tenant: platform_tenant
    } do
      attrs =
        create_attrs(platform_tenant.id)
        |> Map.put(:identifications, [
          %{
            id_type: "passport",
            id_number: "A1234567",
            issuing_country: "US",
            expiration_date: "2030-12-31"
          }
        ])

      conn = post(conn, ~p"/api/legal-entities", attrs)
      response = json_response(conn, 201)

      assert %{"identifications" => [identification]} = response
      assert identification["id_type"] == "passport"
      assert identification["issuing_country"] == "US"
    end

    test "renders errors when legal_entity_type is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/legal-entities", @invalid_attrs)
      response = json_response(conn, 422)
      assert %{"errors" => errors} = response
      assert is_list(errors)
      assert errors != []
    end

    test "renders errors when legal_entity_type is invalid", %{
      conn: conn,
      platform_tenant: platform_tenant
    } do
      attrs = Map.put(create_attrs(platform_tenant.id), :legal_entity_type, "invalid_type")
      conn = post(conn, ~p"/api/legal-entities", attrs)
      assert json_response(conn, 422)
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/legal-entities", @individual_attrs)

      assert json_response(conn, 401)
    end
  end

  describe "update (PUT /api/legal-entities/:id)" do
    setup [:create_legal_entity]

    test "updates legal entity with valid data", %{
      conn: conn,
      legal_entity: legal_entity,
      platform_tenant: platform_tenant
    } do
      conn =
        put(conn, ~p"/api/legal-entities/#{legal_entity.id}", update_attrs(platform_tenant.id))

      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "LegalEntityResponse", api_spec)

      assert %{
               "id" => id,
               "first_name" => "Jane",
               "last_name" => "Smith",
               "citizenship_country" => "CA",
               "politically_exposed_person" => true
             } = response

      assert id == legal_entity.id
    end

    test "replaces nested addresses on update", %{
      conn: conn,
      legal_entity: legal_entity,
      platform_tenant: platform_tenant
    } do
      attrs =
        update_attrs(platform_tenant.id)
        |> Map.put(:addresses, [
          %{
            address_types: ["mailing"],
            primary: true,
            line1: "456 New St",
            country: "CA"
          }
        ])

      conn = put(conn, ~p"/api/legal-entities/#{legal_entity.id}", attrs)
      response = json_response(conn, 200)

      assert %{"addresses" => [address]} = response
      assert address["line1"] == "456 New St"
      assert address["country"] == "CA"
    end

    test "renders errors when data is invalid", %{conn: conn, legal_entity: legal_entity} do
      conn = put(conn, ~p"/api/legal-entities/#{legal_entity.id}", @invalid_attrs)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert is_list(errors)
      assert errors != []
    end

    test "renders 404 when entity does not exist", %{conn: conn, platform_tenant: platform_tenant} do
      non_existent_id = Ecto.UUID.generate()

      conn =
        put(conn, ~p"/api/legal-entities/#{non_existent_id}", update_attrs(platform_tenant.id))

      assert json_response(conn, 404)
    end

    test "returns 401 without API key", %{legal_entity: legal_entity} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/legal-entities/#{legal_entity.id}", @update_fields)

      assert json_response(conn, 401)
    end
  end

  describe "delete (DELETE /api/legal-entities/:id)" do
    setup [:create_legal_entity]

    test "deletes legal entity and cascades to associations", %{
      conn: conn,
      legal_entity: legal_entity,
      plain_api_key: plain_api_key
    } do
      delete_conn = delete(conn, ~p"/api/legal-entities/#{legal_entity.id}")
      assert response(delete_conn, 204)

      # Verify deleted via GET
      get_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> get(~p"/api/legal-entities/#{legal_entity.id}")

      assert json_response(get_conn, 404)
    end

    test "renders 404 when entity does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = delete(conn, ~p"/api/legal-entities/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "cannot delete entity twice", %{
      conn: conn,
      legal_entity: legal_entity,
      plain_api_key: plain_api_key
    } do
      conn = delete(conn, ~p"/api/legal-entities/#{legal_entity.id}")
      assert response(conn, 204)

      conn2 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> delete(~p"/api/legal-entities/#{legal_entity.id}")

      assert json_response(conn2, 404)
    end

    test "returns 401 without API key", %{legal_entity: legal_entity} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> delete(~p"/api/legal-entities/#{legal_entity.id}")

      assert json_response(conn, 401)
    end
  end

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes legal entity endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"openapi" => "3.1.0", "paths" => paths} = response

      assert paths["/api/legal-entities"]
      assert paths["/api/legal-entities"]["get"]
      assert paths["/api/legal-entities"]["post"]
      assert paths["/api/legal-entities/{id}"]
      assert paths["/api/legal-entities/{id}"]["get"]
      assert paths["/api/legal-entities/{id}"]["put"]
      assert paths["/api/legal-entities/{id}"]["delete"]
    end

    test "OpenAPI spec includes LegalEntity schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => schemas}} = response

      assert schemas["LegalEntityRequest"]
      assert schemas["LegalEntityResponse"]
      assert schemas["LegalEntityListResponse"]
    end

    test "LegalEntityRequest excludes server-generated readOnly fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => %{"LegalEntityRequest" => request_schema}}} =
               response

      # Server-generated readOnly fields should not appear in Request schema
      refute get_in(request_schema, ["properties", "id"])
      refute get_in(request_schema, ["properties", "inserted_at"])
      refute get_in(request_schema, ["properties", "updated_at"])

      # Writable fields should be present
      assert get_in(request_schema, ["properties", "legal_entity_type"])
      assert get_in(request_schema, ["properties", "first_name"])
      assert get_in(request_schema, ["properties", "last_name"])
      assert get_in(request_schema, ["properties", "tenant_id"])
    end

    test "LegalEntityResponse includes all fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => %{"LegalEntityResponse" => response_schema}}} =
               response

      assert get_in(response_schema, ["properties", "id"])
      assert get_in(response_schema, ["properties", "legal_entity_type"])
      assert get_in(response_schema, ["properties", "first_name"])
      assert get_in(response_schema, ["properties", "inserted_at"])
      assert get_in(response_schema, ["properties", "updated_at"])
    end
  end

  defp create_legal_entity(%{platform_tenant: platform_tenant}) do
    legal_entity = insert(:legal_entity, tenant_id: platform_tenant.id)
    %{legal_entity: legal_entity}
  end
end
