defmodule PaymentCompliancePlatformApi.ApiInfoControllerTest do
  use PaymentCompliancePlatformWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions

  alias PaymentCompliancePlatformApi.ApiSpec

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

    test "returns consistent structure on multiple calls", %{conn: _conn} do
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

  describe "GET /api/info/normalization-rules" do
    test "returns normalization rules", %{conn: conn} do
      conn = get(conn, ~p"/api/info/normalization-rules")
      response = json_response(conn, 200)

      # Validate entire response against OpenAPI schema
      assert_schema(response, "NormalizationRulesResponse", ApiSpec.spec())

      # Then business logic assertions
      assert %{
               "titles" => titles,
               "suffixes" => suffixes,
               "entity_types" => entity_types
             } = response

      # Verify all fields are arrays of strings
      assert is_list(titles) and Enum.all?(titles, &is_binary/1)
      assert is_list(suffixes) and Enum.all?(suffixes, &is_binary/1)
      assert is_list(entity_types) and Enum.all?(entity_types, &is_binary/1)

      # Verify some expected values are present
      assert "mr" in titles
      assert "mrs" in titles
      assert "dr" in titles

      assert "jr" in suffixes
      assert "sr" in suffixes

      assert "llc" in entity_types
      assert "inc" in entity_types
      assert "corp" in entity_types
    end

    test "returns consistent data on multiple calls", %{conn: _conn} do
      # Make multiple requests
      conn1 = get(build_conn(), ~p"/api/info/normalization-rules")
      response1 = json_response(conn1, 200)

      conn2 = get(build_conn(), ~p"/api/info/normalization-rules")
      response2 = json_response(conn2, 200)

      # Both responses should be valid
      assert_schema(response1, "NormalizationRulesResponse", ApiSpec.spec())
      assert_schema(response2, "NormalizationRulesResponse", ApiSpec.spec())

      # Data should be identical (loaded at compile time)
      assert response1 == response2
    end

    test "all values are lowercase", %{conn: conn} do
      conn = get(conn, ~p"/api/info/normalization-rules")
      response = json_response(conn, 200)

      # Verify all titles are lowercase
      assert Enum.all?(response["titles"], fn title ->
               title == String.downcase(title)
             end)

      # Verify all suffixes are lowercase
      assert Enum.all?(response["suffixes"], fn suffix ->
               suffix == String.downcase(suffix)
             end)

      # Verify all entity types are lowercase
      assert Enum.all?(response["entity_types"], fn entity_type ->
               entity_type == String.downcase(entity_type)
             end)
    end

    test "no duplicate values in any list", %{conn: conn} do
      conn = get(conn, ~p"/api/info/normalization-rules")
      response = json_response(conn, 200)

      # Verify no duplicates in titles
      assert length(response["titles"]) == length(Enum.uniq(response["titles"]))

      # Verify no duplicates in suffixes
      assert length(response["suffixes"]) == length(Enum.uniq(response["suffixes"]))

      # Verify no duplicates in entity_types
      assert length(response["entity_types"]) == length(Enum.uniq(response["entity_types"]))
    end
  end
end
