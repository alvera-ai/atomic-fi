defmodule AtomicFiApi.CounterpartyControllerTest do
  use AtomicFiWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import AtomicFi.Factory

  alias AtomicFiApi.ApiSpec

  @valid_attrs %{status: "active"}
  @update_attrs %{status: "suspended"}
  @invalid_attrs %{status: nil}

  defp create_attrs(tenant_id, account_holder_id, legal_entity_id) do
    @valid_attrs
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

  describe "index (GET /api/counterparties)" do
    test "lists counterparties for tenant", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      _cp1 =
        insert(:counterparty,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id,
          legal_entity_id: legal_entity.id
        )

      legal_entity2 = insert(:legal_entity, tenant_id: platform_tenant.id)

      _cp2 =
        insert(:counterparty,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id,
          legal_entity_id: legal_entity2.id
        )

      conn = get(conn, ~p"/api/counterparties")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "CounterpartyListResponse", api_spec)

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

        insert(:counterparty,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id,
          legal_entity_id: le.id
        )
      end

      conn = get(conn, ~p"/api/counterparties", %{"page" => 1, "page_size" => 5})
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "CounterpartyListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert length(data) == 5
      assert meta["page"] == 1
      assert meta["page_size"] == 5
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/counterparties")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/counterparties/:id)" do
    setup [:create_counterparty]

    test "renders counterparty", %{conn: conn, counterparty: counterparty} do
      conn = get(conn, ~p"/api/counterparties/#{counterparty.id}")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "CounterpartyResponse", api_spec)

      assert %{
               "id" => id,
               "status" => "active"
             } = response

      assert id == counterparty.id
    end

    test "renders 404 when counterparty does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/counterparties/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "renders 422 when id is invalid format", %{conn: conn} do
      conn = get(conn, ~p"/api/counterparties/invalid-uuid")
      assert conn.status == 422
    end

    test "returns 401 without API key", %{counterparty: counterparty} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/counterparties/#{counterparty.id}")

      assert json_response(conn, 401)
    end
  end

  describe "create (POST /api/counterparties)" do
    test "creates counterparty with valid data", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      conn =
        post(
          conn,
          ~p"/api/counterparties",
          create_attrs(platform_tenant.id, account_holder.id, legal_entity.id)
        )

      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "CounterpartyResponse", api_spec)

      assert %{
               "id" => id,
               "status" => "active",
               "account_holder_id" => account_holder_id,
               "legal_entity_id" => legal_entity_id
             } = response

      assert is_binary(id)
      assert account_holder_id == account_holder.id
      assert legal_entity_id == legal_entity.id
      assert Plug.Conn.get_resp_header(conn, "location") == ["/api/counterparties/#{id}"]
    end

    test "creates counterparty with optional external_id", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      attrs =
        create_attrs(platform_tenant.id, account_holder.id, legal_entity.id)
        |> Map.put(:external_id, "CP-EXT-001")

      conn = post(conn, ~p"/api/counterparties", attrs)
      response = json_response(conn, 201)

      assert %{"external_id" => "CP-EXT-001"} = response
    end

    test "renders errors when status is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/counterparties", @invalid_attrs)
      response = json_response(conn, 422)
      assert %{"errors" => errors} = response
      assert is_list(errors)
      assert errors != []
    end

    test "renders errors when status is invalid enum", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      attrs =
        create_attrs(platform_tenant.id, account_holder.id, legal_entity.id)
        |> Map.put(:status, "invalid_status")

      conn = post(conn, ~p"/api/counterparties", attrs)
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
          ~p"/api/counterparties",
          @valid_attrs
          |> Map.put(:account_holder_id, account_holder.id)
          |> Map.put(:legal_entity_id, legal_entity.id)
        )

      assert json_response(conn, 401)
    end

    test "creates counterparty with nested legal_entity (cast_assoc)", %{
      conn: conn,
      session: session,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      attrs = %{
        status: "active",
        account_holder_id: account_holder.id,
        tenant_id: platform_tenant.id,
        chain_screening: false,
        legal_entity: %{
          legal_entity_type: "individual",
          first_name: "Jane",
          last_name: "External",
          date_of_birth: "1985-03-15",
          citizenship_country: "US",
          politically_exposed_person: false,
          tenant_id: platform_tenant.id
        }
      }

      conn = post(conn, ~p"/api/counterparties", attrs)
      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "CounterpartyResponse", api_spec)

      assert %{
               "id" => id,
               "status" => "active",
               "account_holder_id" => returned_ah_id,
               "legal_entity_id" => le_id,
               "legal_entity" => le_payload
             } = response

      assert is_binary(id)
      assert returned_ah_id == account_holder.id
      assert is_binary(le_id)

      # Nested LE is serialised in the response (no second round-trip needed).
      assert le_payload["first_name"] == "Jane"
      assert le_payload["last_name"] == "External"
      assert le_payload["tenant_id"] == platform_tenant.id

      # Cross-check via the real session that the LE was actually persisted.
      le = AtomicFi.LegalEntityContext.get_legal_entity!(session, le_id)
      assert le.first_name == "Jane"
      assert le.last_name == "External"
      assert le.tenant_id == platform_tenant.id
    end

    test "POST is get-or-create on external_id (idempotent)", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      attrs =
        create_attrs(platform_tenant.id, account_holder.id, legal_entity.id)
        |> Map.put(:external_id, "CP-EXT-IDEMPOTENT-1")

      conn1 = post(conn, ~p"/api/counterparties", attrs)
      response1 = json_response(conn1, 201)
      api_spec = ApiSpec.spec()
      assert_schema(response1, "CounterpartyResponse", api_spec)
      id1 = response1["id"]

      # Re-POST with same external_id, even with different status / FK
      # values, returns the original record unchanged (external SoE id wins).
      other_le = insert(:legal_entity, tenant_id: platform_tenant.id)

      attrs2 =
        attrs
        |> Map.put(:legal_entity_id, other_le.id)
        |> Map.put(:status, "suspended")

      conn2 = post(conn, ~p"/api/counterparties", attrs2)
      response2 = json_response(conn2, 201)
      assert_schema(response2, "CounterpartyResponse", api_spec)

      assert response2["id"] == id1
      assert response2["legal_entity_id"] == legal_entity.id
      assert response2["status"] == "active"
      assert response2["external_id"] == "CP-EXT-IDEMPOTENT-1"
    end

    test "renders 422 when neither legal_entity_id nor nested legal_entity is supplied", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      attrs = %{
        status: "active",
        account_holder_id: account_holder.id,
        tenant_id: platform_tenant.id,
        chain_screening: false
      }

      conn = post(conn, ~p"/api/counterparties", attrs)
      assert json_response(conn, 422)
    end
  end

  describe "update (PUT /api/counterparties/:id)" do
    setup [:create_counterparty]

    test "updates counterparty with valid data", %{
      conn: conn,
      counterparty: counterparty,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      conn =
        put(
          conn,
          ~p"/api/counterparties/#{counterparty.id}",
          update_attrs(platform_tenant.id, account_holder.id, legal_entity.id)
        )

      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "CounterpartyResponse", api_spec)

      assert %{
               "id" => id,
               "status" => "suspended"
             } = response

      assert id == counterparty.id
    end

    test "renders errors when data is invalid", %{conn: conn, counterparty: counterparty} do
      conn = put(conn, ~p"/api/counterparties/#{counterparty.id}", @invalid_attrs)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert is_list(errors)
      assert errors != []
    end

    test "renders 404 when counterparty does not exist", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      non_existent_id = Ecto.UUID.generate()

      conn =
        put(
          conn,
          ~p"/api/counterparties/#{non_existent_id}",
          update_attrs(platform_tenant.id, account_holder.id, legal_entity.id)
        )

      assert json_response(conn, 404)
    end

    test "returns 401 without API key", %{
      counterparty: counterparty,
      account_holder: account_holder,
      legal_entity: legal_entity
    } do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put(
          ~p"/api/counterparties/#{counterparty.id}",
          @update_attrs
          |> Map.put(:account_holder_id, account_holder.id)
          |> Map.put(:legal_entity_id, legal_entity.id)
        )

      assert json_response(conn, 401)
    end
  end

  describe "delete (DELETE /api/counterparties/:id)" do
    setup [:create_counterparty]

    test "deletes counterparty", %{
      conn: conn,
      counterparty: counterparty,
      plain_api_key: plain_api_key
    } do
      delete_conn = delete(conn, ~p"/api/counterparties/#{counterparty.id}")
      assert response(delete_conn, 204)

      get_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> get(~p"/api/counterparties/#{counterparty.id}")

      assert json_response(get_conn, 404)
    end

    test "renders 404 when counterparty does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = delete(conn, ~p"/api/counterparties/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "cannot delete counterparty twice", %{
      conn: conn,
      counterparty: counterparty,
      plain_api_key: plain_api_key
    } do
      conn = delete(conn, ~p"/api/counterparties/#{counterparty.id}")
      assert response(conn, 204)

      conn2 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> delete(~p"/api/counterparties/#{counterparty.id}")

      assert json_response(conn2, 404)
    end

    test "returns 401 without API key", %{counterparty: counterparty} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> delete(~p"/api/counterparties/#{counterparty.id}")

      assert json_response(conn, 401)
    end
  end

  describe "refresh (POST /api/counterparties/:id/refresh)" do
    setup [:create_counterparty]

    setup %{platform_tenant: platform_tenant} do
      init_blocklist_cache(platform_tenant.id)
      :ok
    end

    test "re-runs the onboarding flow and returns the refreshed CP", %{
      conn: conn,
      counterparty: counterparty
    } do
      conn = post(conn, ~p"/api/counterparties/#{counterparty.id}/refresh", %{})
      response = json_response(conn, 200)

      assert response["id"] == counterparty.id
      assert_schema(response, "CounterpartyResponse", ApiSpec.spec())
    end

    test "returns 404 when counterparty does not exist", %{conn: conn} do
      conn = post(conn, ~p"/api/counterparties/#{Ecto.UUID.generate()}/refresh", %{})
      assert json_response(conn, 404)
    end

    test "returns 401 without API key", %{counterparty: counterparty} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/counterparties/#{counterparty.id}/refresh", %{})

      assert json_response(conn, 401)
    end
  end

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes counterparty endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"openapi" => "3.1.0", "paths" => paths} = response

      assert paths["/api/counterparties"]
      assert paths["/api/counterparties"]["get"]
      assert paths["/api/counterparties"]["post"]
      assert paths["/api/counterparties/{id}"]
      assert paths["/api/counterparties/{id}"]["get"]
      assert paths["/api/counterparties/{id}"]["put"]
      assert paths["/api/counterparties/{id}"]["delete"]
    end

    test "OpenAPI spec includes Counterparty schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => schemas}} = response

      assert schemas["CounterpartyRequest"]
      assert schemas["CounterpartyResponse"]
      assert schemas["CounterpartyListResponse"]
    end

    test "CounterpartyRequest excludes server-generated readOnly fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{"schemas" => %{"CounterpartyRequest" => request_schema}}
             } = response

      refute get_in(request_schema, ["properties", "id"])
      refute get_in(request_schema, ["properties", "inserted_at"])
      refute get_in(request_schema, ["properties", "updated_at"])

      assert get_in(request_schema, ["properties", "account_holder_id"])
      assert get_in(request_schema, ["properties", "legal_entity_id"])
      assert get_in(request_schema, ["properties", "status"])
    end

    test "CounterpartyResponse includes all fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{"schemas" => %{"CounterpartyResponse" => response_schema}}
             } = response

      assert get_in(response_schema, ["properties", "id"])
      assert get_in(response_schema, ["properties", "account_holder_id"])
      assert get_in(response_schema, ["properties", "legal_entity_id"])
      assert get_in(response_schema, ["properties", "status"])
      assert get_in(response_schema, ["properties", "inserted_at"])
      assert get_in(response_schema, ["properties", "updated_at"])
    end
  end

  defp create_counterparty(%{
         platform_tenant: platform_tenant,
         account_holder: account_holder,
         legal_entity: legal_entity
       }) do
    counterparty =
      insert(:counterparty,
        tenant_id: platform_tenant.id,
        account_holder_id: account_holder.id,
        legal_entity_id: legal_entity.id
      )

    %{counterparty: counterparty}
  end
end
