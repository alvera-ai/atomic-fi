defmodule AtomicFiApi.DocumentControllerTest do
  use AtomicFiWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import AtomicFi.Factory

  alias AtomicFiApi.ApiSpec

  @base_attrs %{
    document_type: "identity_document",
    name: "kyc_passport",
    primary: true
  }

  @update_attrs %{
    document_type: "identity_document",
    name: "kyc_passport",
    status: "submitted",
    primary: true
  }

  @invalid_attrs %{document_type: nil, name: nil, primary: nil}

  defp create_attrs(tenant_id, account_holder_id) do
    @base_attrs
    |> Map.put(:tenant_id, tenant_id)
    |> Map.put(:account_holder_id, account_holder_id)
  end

  defp update_attrs(tenant_id, account_holder_id) do
    @update_attrs
    |> Map.put(:tenant_id, tenant_id)
    |> Map.put(:account_holder_id, account_holder_id)
  end

  setup :setup_platform_admin_api

  setup %{platform_tenant: platform_tenant} do
    account_holder = insert(:account_holder, tenant_id: platform_tenant.id)
    %{account_holder: account_holder}
  end

  describe "index (GET /api/documents)" do
    test "lists documents for tenant", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      _doc1 =
        insert(:document,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id,
          document_type: :identity_document,
          name: "kyc_passport",
          primary: true
        )

      _doc2 =
        insert(:document,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id,
          document_type: :proof_of_address,
          name: "utility_bill",
          primary: true
        )

      conn = get(conn, ~p"/api/documents")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "DocumentListResponse", api_spec)

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
      names = ["doc1", "doc2", "doc3", "doc4", "doc5"]

      for name <- names do
        insert(:document,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id,
          document_type: :identity_document,
          name: name,
          primary: true
        )
      end

      conn = get(conn, ~p"/api/documents", %{"page" => 1, "page_size" => 3})
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "DocumentListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert length(data) == 3
      assert meta["page"] == 1
      assert meta["page_size"] == 3
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/documents")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/documents/:id)" do
    setup [:create_document]

    test "renders document", %{conn: conn, document: document} do
      conn = get(conn, ~p"/api/documents/#{document.id}")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "DocumentResponse", api_spec)

      assert %{
               "id" => id,
               "document_type" => "identity_document",
               "name" => "kyc_passport",
               "primary" => true
             } = response

      assert id == document.id
    end

    test "renders 404 when document does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/documents/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "renders 422 when id is invalid format", %{conn: conn} do
      conn = get(conn, ~p"/api/documents/invalid-uuid")
      assert conn.status == 422
    end

    test "returns 401 without API key", %{document: document} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/documents/#{document.id}")

      assert json_response(conn, 401)
    end
  end

  describe "create (POST /api/documents)" do
    test "creates document", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      conn =
        post(
          conn,
          ~p"/api/documents",
          create_attrs(platform_tenant.id, account_holder.id)
        )

      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "DocumentResponse", api_spec)

      assert %{
               "id" => id,
               "document_type" => "identity_document",
               "name" => "kyc_passport",
               "primary" => true,
               "status" => "draft",
               "account_holder_id" => account_holder_id
             } = response

      assert is_binary(id)
      assert account_holder_id == account_holder.id
      assert Plug.Conn.get_resp_header(conn, "location") == ["/api/documents/#{id}"]
    end

    test "creates document with optional fields", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      attrs =
        create_attrs(platform_tenant.id, account_holder.id)
        |> Map.merge(%{
          document_type: "proof_of_address",
          name: "utility_bill",
          description: "Recent utility bill",
          status: "submitted",
          file_key: "uploads/test/bill.pdf",
          file_name: "bill.pdf",
          file_size: 102_400,
          content_type: "application/pdf",
          document_number: "DOC-2026-001"
        })

      conn = post(conn, ~p"/api/documents", attrs)
      response = json_response(conn, 201)

      assert %{
               "document_type" => "proof_of_address",
               "status" => "submitted",
               "file_key" => "uploads/test/bill.pdf",
               "file_name" => "bill.pdf",
               "document_number" => "DOC-2026-001"
             } = response
    end

    test "renders errors when document_type is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/documents", @invalid_attrs)
      response = json_response(conn, 422)
      assert %{"errors" => errors} = response
      assert is_list(errors)
      assert errors != []
    end

    test "renders errors when document_type is invalid enum", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      attrs =
        create_attrs(platform_tenant.id, account_holder.id)
        |> Map.put(:document_type, "invalid_type")

      conn = post(conn, ~p"/api/documents", attrs)
      assert json_response(conn, 422)
    end

    test "returns 401 without API key", %{account_holder: account_holder} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/documents",
          @base_attrs |> Map.put(:account_holder_id, account_holder.id)
        )

      assert json_response(conn, 401)
    end
  end

  describe "update (PUT /api/documents/:id)" do
    setup [:create_document]

    test "updates document with valid data", %{
      conn: conn,
      document: document,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      conn =
        put(
          conn,
          ~p"/api/documents/#{document.id}",
          update_attrs(platform_tenant.id, account_holder.id)
        )

      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "DocumentResponse", api_spec)

      assert %{
               "id" => id,
               "status" => "submitted"
             } = response

      assert id == document.id
    end

    test "renders errors when data is invalid", %{conn: conn, document: document} do
      conn = put(conn, ~p"/api/documents/#{document.id}", @invalid_attrs)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert is_list(errors)
      assert errors != []
    end

    test "renders 404 when document does not exist", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      non_existent_id = Ecto.UUID.generate()

      conn =
        put(
          conn,
          ~p"/api/documents/#{non_existent_id}",
          update_attrs(platform_tenant.id, account_holder.id)
        )

      assert json_response(conn, 404)
    end

    test "returns 401 without API key", %{document: document, account_holder: account_holder} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put(
          ~p"/api/documents/#{document.id}",
          @update_attrs |> Map.put(:account_holder_id, account_holder.id)
        )

      assert json_response(conn, 401)
    end
  end

  describe "delete (DELETE /api/documents/:id)" do
    setup [:create_document]

    test "deletes document", %{conn: conn, document: document, plain_api_key: plain_api_key} do
      delete_conn = delete(conn, ~p"/api/documents/#{document.id}")
      assert response(delete_conn, 204)

      get_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> get(~p"/api/documents/#{document.id}")

      assert json_response(get_conn, 404)
    end

    test "renders 404 when document does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = delete(conn, ~p"/api/documents/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "cannot delete document twice", %{
      conn: conn,
      document: document,
      plain_api_key: plain_api_key
    } do
      conn = delete(conn, ~p"/api/documents/#{document.id}")
      assert response(conn, 204)

      conn2 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> delete(~p"/api/documents/#{document.id}")

      assert json_response(conn2, 404)
    end

    test "returns 401 without API key", %{document: document} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> delete(~p"/api/documents/#{document.id}")

      assert json_response(conn, 401)
    end
  end

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes document endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"openapi" => "3.1.0", "paths" => paths} = response

      assert paths["/api/documents"]
      assert paths["/api/documents"]["get"]
      assert paths["/api/documents"]["post"]
      assert paths["/api/documents/{id}"]
      assert paths["/api/documents/{id}"]["get"]
      assert paths["/api/documents/{id}"]["put"]
      assert paths["/api/documents/{id}"]["delete"]
    end

    test "OpenAPI spec includes Document schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => schemas}} = response

      assert schemas["DocumentRequest"]
      assert schemas["DocumentResponse"]
      assert schemas["DocumentListResponse"]
    end

    test "DocumentRequest excludes server-generated readOnly fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{"schemas" => %{"DocumentRequest" => request_schema}}
             } = response

      refute get_in(request_schema, ["properties", "id"])
      refute get_in(request_schema, ["properties", "inserted_at"])
      refute get_in(request_schema, ["properties", "updated_at"])

      assert get_in(request_schema, ["properties", "document_type"])
      assert get_in(request_schema, ["properties", "name"])
      assert get_in(request_schema, ["properties", "account_holder_id"])
    end

    test "DocumentResponse includes all fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{"schemas" => %{"DocumentResponse" => response_schema}}
             } = response

      assert get_in(response_schema, ["properties", "id"])
      assert get_in(response_schema, ["properties", "document_type"])
      assert get_in(response_schema, ["properties", "name"])
      assert get_in(response_schema, ["properties", "status"])
      assert get_in(response_schema, ["properties", "primary"])
      assert get_in(response_schema, ["properties", "account_holder_id"])
      assert get_in(response_schema, ["properties", "inserted_at"])
      assert get_in(response_schema, ["properties", "updated_at"])
    end
  end

  defp create_document(%{platform_tenant: platform_tenant, account_holder: account_holder}) do
    document =
      insert(:document,
        tenant_id: platform_tenant.id,
        account_holder_id: account_holder.id,
        document_type: :identity_document,
        name: "kyc_passport",
        primary: true
      )

    %{document: document}
  end
end
