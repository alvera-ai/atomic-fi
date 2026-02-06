defmodule PaymentCompliancePlatformApi.OpenApiSpecControllerTest do
  use PaymentCompliancePlatformWeb.ConnCase, async: true

  describe "GET /api/openapi" do
    test "returns valid OpenAPI spec", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      # Verify OpenAPI version (configured as 3.1.0)
      assert response["openapi"] == "3.1.0"

      # Verify info section
      assert %{"title" => _title, "version" => _version} = response["info"]

      # Verify servers section exists
      assert is_list(response["servers"])
      assert response["servers"] != []

      # Verify components section with security schemes
      assert %{"securitySchemes" => security_schemes} = response["components"]
      assert %{"ApiKeyAuth" => api_key_auth} = security_schemes
      assert api_key_auth["type"] == "apiKey"
      assert api_key_auth["name"] == "x-api-key"
      assert api_key_auth["in"] == "header"
    end

    test "includes API info endpoint in paths", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      # Verify /api/info endpoint is documented
      assert %{"paths" => paths} = response
      assert Map.has_key?(paths, "/api/info")

      # Verify it has GET operation
      assert %{"/api/info" => %{"get" => get_operation}} = paths
      assert get_operation["summary"] == "API information"
      assert get_operation["tags"] == ["Health"]
    end

    test "spec is valid JSON and can be parsed", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")

      # Response should be valid JSON (already parsed by json_response/2)
      response = json_response(conn, 200)

      # Should be able to convert back to JSON string
      json_string = Jason.encode!(response)
      assert is_binary(json_string)

      # Should be able to parse it back
      {:ok, reparsed} = Jason.decode(json_string)
      assert reparsed["openapi"] == "3.1.0"
    end

    test "returns consistent spec on multiple requests", %{conn: conn} do
      # Make multiple requests
      conn1 = get(build_conn(), ~p"/api/openapi")
      response1 = json_response(conn1, 200)

      conn2 = get(build_conn(), ~p"/api/openapi")
      response2 = json_response(conn2, 200)

      # Should be identical
      assert response1 == response2
    end
  end
end
