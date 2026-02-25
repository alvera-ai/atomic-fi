defmodule PaymentCompliancePlatformApi.LegalEntityChangeEventControllerTest do
  use PaymentCompliancePlatformWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import PaymentCompliancePlatform.Factory

  alias PaymentCompliancePlatformApi.ApiSpec

  @base_attrs %{
    event_type: "address_change",
    change_channel: "web"
  }

  @update_attrs %{
    event_type: "address_change",
    change_channel: "branch",
    event_status: "confirmed"
  }

  @invalid_attrs %{event_type: nil, change_channel: nil, legal_entity_id: nil}

  defp create_attrs(tenant_id, legal_entity_id) do
    @base_attrs
    |> Map.put(:tenant_id, tenant_id)
    |> Map.put(:legal_entity_id, legal_entity_id)
  end

  defp update_attrs(tenant_id, legal_entity_id) do
    @update_attrs
    |> Map.put(:tenant_id, tenant_id)
    |> Map.put(:legal_entity_id, legal_entity_id)
  end

  setup :setup_platform_admin_api

  setup %{platform_tenant: platform_tenant} do
    legal_entity = insert(:legal_entity, tenant_id: platform_tenant.id)
    %{legal_entity: legal_entity}
  end

  describe "index (GET /api/legal-entity-change-events)" do
    test "lists events for tenant", %{
      conn: conn,
      platform_tenant: platform_tenant,
      legal_entity: legal_entity
    } do
      insert(:legal_entity_change_event,
        tenant_id: platform_tenant.id,
        legal_entity_id: legal_entity.id,
        event_type: :address_change
      )

      insert(:legal_entity_change_event,
        tenant_id: platform_tenant.id,
        legal_entity_id: legal_entity.id,
        event_type: :phone_change
      )

      conn = get(conn, ~p"/api/legal-entity-change-events")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "LegalEntityChangeEventListResponse", api_spec)

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
      for _i <- 1..5 do
        insert(:legal_entity_change_event,
          tenant_id: platform_tenant.id,
          legal_entity_id: legal_entity.id
        )
      end

      conn = get(conn, ~p"/api/legal-entity-change-events", %{"page" => 1, "page_size" => 3})
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "LegalEntityChangeEventListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert length(data) == 3
      assert meta["page"] == 1
      assert meta["page_size"] == 3
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/legal-entity-change-events")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/legal-entity-change-events/:id)" do
    setup [:create_event]

    test "renders event", %{conn: conn, event: event} do
      conn = get(conn, ~p"/api/legal-entity-change-events/#{event.id}")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "LegalEntityChangeEventResponse", api_spec)

      assert %{
               "id" => id,
               "event_type" => "address_change",
               "change_channel" => "web"
             } = response

      assert id == event.id
    end

    test "renders 404 when event does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/legal-entity-change-events/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "renders 422 when id is invalid format", %{conn: conn} do
      conn = get(conn, ~p"/api/legal-entity-change-events/invalid-uuid")
      assert conn.status == 422
    end

    test "returns 401 without API key", %{event: event} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/legal-entity-change-events/#{event.id}")

      assert json_response(conn, 401)
    end
  end

  describe "create (POST /api/legal-entity-change-events)" do
    test "creates event", %{
      conn: conn,
      platform_tenant: platform_tenant,
      legal_entity: legal_entity
    } do
      conn =
        post(
          conn,
          ~p"/api/legal-entity-change-events",
          create_attrs(platform_tenant.id, legal_entity.id)
        )

      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "LegalEntityChangeEventResponse", api_spec)

      assert %{
               "id" => id,
               "event_type" => "address_change",
               "change_channel" => "web",
               "legal_entity_id" => legal_entity_id
             } = response

      assert is_binary(id)
      assert legal_entity_id == legal_entity.id

      assert Plug.Conn.get_resp_header(conn, "location") == [
               "/api/legal-entity-change-events/#{id}"
             ]
    end

    test "creates event with acmt references", %{
      conn: conn,
      platform_tenant: platform_tenant,
      legal_entity: legal_entity
    } do
      attrs =
        create_attrs(platform_tenant.id, legal_entity.id)
        |> Map.merge(%{
          event_type: "phone_change",
          change_channel: "mobile",
          acmt_instruction_id: "MSG-2026-001",
          acmt_confirmation_id: "CONF-2026-001"
        })

      conn = post(conn, ~p"/api/legal-entity-change-events", attrs)
      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "LegalEntityChangeEventResponse", api_spec)

      assert %{
               "acmt_instruction_id" => "MSG-2026-001",
               "acmt_confirmation_id" => "CONF-2026-001"
             } = response
    end

    test "creates event with all event types", %{
      conn: conn,
      platform_tenant: platform_tenant,
      legal_entity: legal_entity
    } do
      event_types = [
        "address_change",
        "phone_change",
        "email_change",
        "beneficiary_added",
        "beneficiary_removed",
        "beneficiary_modified",
        "account_inquiry",
        "contact_info_change",
        "authorised_signer_change"
      ]

      for type <- event_types do
        attrs =
          create_attrs(platform_tenant.id, legal_entity.id)
          |> Map.put(:event_type, type)

        conn2 = post(conn, ~p"/api/legal-entity-change-events", attrs)
        response = json_response(conn2, 201)
        assert response["event_type"] == type
      end
    end

    test "renders errors when required fields are missing", %{conn: conn} do
      conn = post(conn, ~p"/api/legal-entity-change-events", @invalid_attrs)
      response = json_response(conn, 422)
      assert %{"errors" => errors} = response
      assert is_list(errors)
      assert errors != []
    end

    test "renders errors when event_type is invalid enum", %{
      conn: conn,
      platform_tenant: platform_tenant,
      legal_entity: legal_entity
    } do
      attrs =
        create_attrs(platform_tenant.id, legal_entity.id)
        |> Map.put(:event_type, "invalid_type")

      conn = post(conn, ~p"/api/legal-entity-change-events", attrs)
      assert json_response(conn, 422)
    end

    test "returns 401 without API key", %{legal_entity: legal_entity} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/legal-entity-change-events",
          @base_attrs |> Map.put(:legal_entity_id, legal_entity.id)
        )

      assert json_response(conn, 401)
    end
  end

  describe "update (PUT /api/legal-entity-change-events/:id)" do
    setup [:create_event]

    test "updates event with valid mutable fields", %{
      conn: conn,
      event: event,
      platform_tenant: platform_tenant,
      legal_entity: legal_entity
    } do
      conn =
        put(
          conn,
          ~p"/api/legal-entity-change-events/#{event.id}",
          update_attrs(platform_tenant.id, legal_entity.id)
        )

      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "LegalEntityChangeEventResponse", api_spec)

      assert %{
               "id" => id,
               "change_channel" => "branch",
               "event_status" => "confirmed"
             } = response

      assert id == event.id
    end

    test "renders 404 when event does not exist", %{
      conn: conn,
      platform_tenant: platform_tenant,
      legal_entity: legal_entity
    } do
      non_existent_id = Ecto.UUID.generate()

      conn =
        put(
          conn,
          ~p"/api/legal-entity-change-events/#{non_existent_id}",
          update_attrs(platform_tenant.id, legal_entity.id)
        )

      assert json_response(conn, 404)
    end

    test "returns 401 without API key", %{event: event, legal_entity: legal_entity} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put(
          ~p"/api/legal-entity-change-events/#{event.id}",
          @update_attrs |> Map.put(:legal_entity_id, legal_entity.id)
        )

      assert json_response(conn, 401)
    end
  end

  describe "delete (DELETE /api/legal-entity-change-events/:id)" do
    setup [:create_event]

    test "deletes event", %{conn: conn, event: event, plain_api_key: plain_api_key} do
      delete_conn = delete(conn, ~p"/api/legal-entity-change-events/#{event.id}")
      assert response(delete_conn, 204)

      get_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> get(~p"/api/legal-entity-change-events/#{event.id}")

      assert json_response(get_conn, 404)
    end

    test "renders 404 when event does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = delete(conn, ~p"/api/legal-entity-change-events/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "cannot delete event twice", %{conn: conn, event: event, plain_api_key: plain_api_key} do
      conn = delete(conn, ~p"/api/legal-entity-change-events/#{event.id}")
      assert response(conn, 204)

      conn2 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> delete(~p"/api/legal-entity-change-events/#{event.id}")

      assert json_response(conn2, 404)
    end

    test "returns 401 without API key", %{event: event} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> delete(~p"/api/legal-entity-change-events/#{event.id}")

      assert json_response(conn, 401)
    end
  end

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes legal entity change event endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"openapi" => "3.1.0", "paths" => paths} = response

      assert paths["/api/legal-entity-change-events"]
      assert paths["/api/legal-entity-change-events"]["get"]
      assert paths["/api/legal-entity-change-events"]["post"]
      assert paths["/api/legal-entity-change-events/{id}"]
      assert paths["/api/legal-entity-change-events/{id}"]["get"]
      assert paths["/api/legal-entity-change-events/{id}"]["put"]
      assert paths["/api/legal-entity-change-events/{id}"]["delete"]
    end

    test "OpenAPI spec includes LegalEntityChangeEvent schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => schemas}} = response

      assert schemas["LegalEntityChangeEventRequest"]
      assert schemas["LegalEntityChangeEventResponse"]
      assert schemas["LegalEntityChangeEventListResponse"]
    end

    test "LegalEntityChangeEventRequest excludes readOnly fields (id, timestamps, changes, previous_state)",
         %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{
                 "schemas" => %{"LegalEntityChangeEventRequest" => request_schema}
               }
             } = response

      refute get_in(request_schema, ["properties", "id"])
      refute get_in(request_schema, ["properties", "inserted_at"])
      refute get_in(request_schema, ["properties", "updated_at"])
      refute get_in(request_schema, ["properties", "changes"])
      refute get_in(request_schema, ["properties", "previous_state"])

      assert get_in(request_schema, ["properties", "event_type"])
      assert get_in(request_schema, ["properties", "change_channel"])
      assert get_in(request_schema, ["properties", "legal_entity_id"])
    end

    test "LegalEntityChangeEventResponse includes all fields including changes and previous_state",
         %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{
                 "schemas" => %{"LegalEntityChangeEventResponse" => response_schema}
               }
             } = response

      assert get_in(response_schema, ["properties", "id"])
      assert get_in(response_schema, ["properties", "event_type"])
      assert get_in(response_schema, ["properties", "change_channel"])
      assert get_in(response_schema, ["properties", "event_status"])
      assert get_in(response_schema, ["properties", "changes"])
      assert get_in(response_schema, ["properties", "previous_state"])
      assert get_in(response_schema, ["properties", "legal_entity_id"])
      assert get_in(response_schema, ["properties", "inserted_at"])
      assert get_in(response_schema, ["properties", "updated_at"])
    end

    test "LegalEntityResponse includes latest_change_event_id", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{
                 "schemas" => %{"LegalEntityResponse" => response_schema}
               }
             } = response

      assert get_in(response_schema, ["properties", "latest_change_event_id"])
    end

    test "LegalEntityRequest excludes latest_change_event_id (readOnly)", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{
                 "schemas" => %{"LegalEntityRequest" => request_schema}
               }
             } = response

      refute get_in(request_schema, ["properties", "latest_change_event_id"])
    end
  end

  defp create_event(%{platform_tenant: platform_tenant, legal_entity: legal_entity}) do
    event =
      insert(:legal_entity_change_event,
        tenant_id: platform_tenant.id,
        legal_entity_id: legal_entity.id,
        event_type: :address_change,
        change_channel: :web
      )

    %{event: event}
  end
end
