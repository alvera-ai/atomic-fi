defmodule PaymentCompliancePlatformApi.RiskClassificationControllerTest do
  use PaymentCompliancePlatformWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import PaymentCompliancePlatform.Factory

  alias PaymentCompliancePlatformApi.ApiSpec

  setup :setup_platform_admin_api

  describe "index (GET /api/risk-classifications)" do
    test "lists classifications", %{conn: conn, platform_tenant: tenant} do
      holder = insert(:account_holder, tenant_id: tenant.id)

      classification =
        insert(:risk_classification, tenant_id: tenant.id, account_holder_id: holder.id)

      conn = get(conn, ~p"/api/risk-classifications")
      response = json_response(conn, 200)

      assert_schema(response, "RiskClassificationListResponse", ApiSpec.spec())
      assert %{"data" => data, "meta" => meta} = response
      assert meta["total_count"] >= 1
      assert Enum.any?(data, fn r -> r["id"] == classification.id end)
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/risk-classifications")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/risk-classifications/:id)" do
    test "renders classification when id exists", %{conn: conn, platform_tenant: tenant} do
      holder = insert(:account_holder, tenant_id: tenant.id)

      classification =
        insert(:risk_classification, tenant_id: tenant.id, account_holder_id: holder.id)

      conn = get(conn, ~p"/api/risk-classifications/#{classification.id}")
      response = json_response(conn, 200)

      assert_schema(response, "RiskClassificationResponse", ApiSpec.spec())
      assert response["id"] == classification.id
      assert response["account_holder_id"] == holder.id
    end

    test "renders 404 when classification does not exist", %{conn: conn} do
      conn = get(conn, ~p"/api/risk-classifications/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "create (POST /api/risk-classifications)" do
    test "creates classification with valid data", %{conn: conn, platform_tenant: tenant} do
      holder = insert(:account_holder, tenant_id: tenant.id)

      attrs = %{
        account_holder_id: holder.id,
        risk_level: "high",
        classification_reason: "Large inbound volume",
        effective_from: Date.to_iso8601(Date.utc_today()),
        is_active: true,
        tenant_id: tenant.id
      }

      conn = post(conn, ~p"/api/risk-classifications", attrs)
      response = json_response(conn, 201)

      assert_schema(response, "RiskClassificationResponse", ApiSpec.spec())
      assert response["risk_level"] == "high"
      assert response["is_active"] == true

      assert Plug.Conn.get_resp_header(conn, "location") == [
               "/api/risk-classifications/#{response["id"]}"
             ]
    end

    test "creating active classification deactivates previous active for the same holder", %{
      conn: conn,
      platform_tenant: tenant
    } do
      holder = insert(:account_holder, tenant_id: tenant.id)

      previous =
        insert(:risk_classification,
          tenant_id: tenant.id,
          account_holder_id: holder.id,
          risk_level: :low,
          is_active: true
        )

      attrs = %{
        account_holder_id: holder.id,
        risk_level: "very_high",
        classification_reason: "Adverse media hit",
        effective_from: Date.to_iso8601(Date.utc_today()),
        is_active: true,
        tenant_id: tenant.id
      }

      conn = post(conn, ~p"/api/risk-classifications", attrs)
      response = json_response(conn, 201)
      assert response["is_active"] == true

      # Previous is now inactive
      conn2 = get(build_conn_for(conn), ~p"/api/risk-classifications/#{previous.id}")
      prev_response = json_response(conn2, 200)
      assert prev_response["is_active"] == false
    end

    test "renders errors when required fields missing", %{conn: conn, platform_tenant: tenant} do
      attrs = %{tenant_id: tenant.id}

      conn = post(conn, ~p"/api/risk-classifications", attrs)
      assert json_response(conn, 422)
    end
  end

  describe "update (PUT /api/risk-classifications/:id)" do
    test "updates classification with valid data", %{conn: conn, platform_tenant: tenant} do
      holder = insert(:account_holder, tenant_id: tenant.id)

      classification =
        insert(:risk_classification,
          tenant_id: tenant.id,
          account_holder_id: holder.id,
          risk_level: :low,
          is_active: true
        )

      attrs = %{
        account_holder_id: holder.id,
        risk_level: "high",
        classification_reason: "Updated",
        effective_from: Date.to_iso8601(classification.effective_from),
        is_active: true,
        tenant_id: tenant.id
      }

      conn = put(conn, ~p"/api/risk-classifications/#{classification.id}", attrs)
      response = json_response(conn, 200)

      assert_schema(response, "RiskClassificationResponse", ApiSpec.spec())
      assert response["risk_level"] == "high"
    end

    test "renders 404 when classification does not exist", %{
      conn: conn,
      platform_tenant: tenant
    } do
      holder = insert(:account_holder, tenant_id: tenant.id)

      attrs = %{
        account_holder_id: holder.id,
        risk_level: "low",
        classification_reason: "any",
        effective_from: Date.to_iso8601(Date.utc_today()),
        tenant_id: tenant.id
      }

      conn = put(conn, ~p"/api/risk-classifications/#{Ecto.UUID.generate()}", attrs)
      assert json_response(conn, 404)
    end
  end

  describe "delete (DELETE /api/risk-classifications/:id)" do
    test "deletes classification", %{conn: conn, platform_tenant: tenant} do
      holder = insert(:account_holder, tenant_id: tenant.id)

      classification =
        insert(:risk_classification, tenant_id: tenant.id, account_holder_id: holder.id)

      conn = delete(conn, ~p"/api/risk-classifications/#{classification.id}")
      assert response(conn, 204)
    end

    test "renders 404 when classification does not exist", %{conn: conn} do
      conn = delete(conn, ~p"/api/risk-classifications/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes risk classification endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"paths" => paths} = response
      assert paths["/api/risk-classifications"]
      assert paths["/api/risk-classifications"]["get"]
      assert paths["/api/risk-classifications"]["post"]
      assert paths["/api/risk-classifications/{id}"]
      assert paths["/api/risk-classifications/{id}"]["get"]
      assert paths["/api/risk-classifications/{id}"]["put"]
      assert paths["/api/risk-classifications/{id}"]["delete"]
    end

    test "OpenAPI spec includes risk classification schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => schemas}} = response
      assert schemas["RiskClassificationRequest"]
      assert schemas["RiskClassificationResponse"]
      assert schemas["RiskClassificationListResponse"]
    end
  end

  # Rebuilds an authenticated conn for a follow-up request in the same test,
  # reusing the x-api-key header from the seeded setup conn.
  defp build_conn_for(conn) do
    case Plug.Conn.get_req_header(conn, "x-api-key") do
      [api_key | _] ->
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("accept", "application/json")
        |> Plug.Conn.put_req_header("x-api-key", api_key)

      _ ->
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("accept", "application/json")
    end
  end
end
