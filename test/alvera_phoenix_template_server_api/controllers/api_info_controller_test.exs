defmodule AlveraPhoenixTemplateServerApi.ApiInfoControllerTest do
  use AlveraPhoenixTemplateServerWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions

  alias AlveraPhoenixTemplateServerApi.ApiSpec

  describe "GET /api/info" do
    test "returns API info with database status", %{conn: conn} do
      conn = get(conn, ~p"/api/info")
      response = json_response(conn, 200)

      # Validate entire response against OpenAPI schema
      assert_schema(response, "ApiInfoResponse", ApiSpec.spec())

      # Then business logic assertions
      assert %{
               "status" => "ok",
               "version" => version,
               "database_status" => "connected",
               "timestamp" => timestamp
             } = response

      # Verify version is a string
      assert is_binary(version)

      # Verify timestamp is valid ISO8601
      assert {:ok, _datetime, 0} = DateTime.from_iso8601(timestamp)
    end

    test "timestamp is recent (within last 5 seconds)", %{conn: conn} do
      conn = get(conn, ~p"/api/info")
      response = json_response(conn, 200)

      # Verify we can parse the timestamp
      assert {:ok, datetime, 0} = DateTime.from_iso8601(response["timestamp"])

      # Verify it's recent (within last 5 seconds)
      now = DateTime.utc_now()
      diff = DateTime.diff(now, datetime, :second)
      assert diff >= 0 and diff < 5
    end

    test "returns consistent structure on multiple calls", %{conn: conn} do
      # Make multiple requests
      conn1 = get(build_conn(), ~p"/api/info")
      response1 = json_response(conn1, 200)

      conn2 = get(build_conn(), ~p"/api/info")
      response2 = json_response(conn2, 200)

      # Both responses should be valid
      assert_schema(response1, "ApiInfoResponse", ApiSpec.spec())
      assert_schema(response2, "ApiInfoResponse", ApiSpec.spec())

      # Version should be consistent
      assert response1["version"] == response2["version"]

      # Database status should be consistent (assuming DB doesn't go down between calls)
      assert response1["database_status"] == response2["database_status"]
    end
  end
end
