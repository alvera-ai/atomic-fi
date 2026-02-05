defmodule PaymentCompliancePlatform.Watchman.OperationsTest do
  @moduledoc """
  Integration tests for Watchman sanctions screening API.

  These tests require the Watchman service to be running:
    make deps.up
  """
  use ExUnit.Case, async: true

  alias PaymentCompliancePlatform.Watchman.{
    Address,
    Entity,
    ListInfoResponse,
    Operations,
    Person,
    SearchResponse
  }

  @moduletag :watchman

  describe "v2_search_get/1" do
    test "returns matching entities for a known sanctioned person" do
      {:ok, %SearchResponse{} = response} = Operations.v2_search_get(name: "Vladimir Putin")

      assert is_list(response.entities)
      assert length(response.entities) > 0

      first = hd(response.entities)
      assert %Entity{} = first
      assert first.name =~ "PUTIN"
      assert first.entityType == "person"
      assert first.sourceList == "us_ofac"
      assert is_float(first.match)
      assert first.match > 0.5
    end

    test "returns empty list for non-matching query" do
      {:ok, %SearchResponse{} = response} =
        Operations.v2_search_get(name: "xyznonexistent12345")

      assert response.entities == [] or response.entities == nil
    end

    test "respects limit parameter" do
      {:ok, %SearchResponse{} = response} =
        Operations.v2_search_get(name: "Vladimir", limit: 3)

      assert length(response.entities) <= 3
    end

    test "filters by entity type" do
      {:ok, %SearchResponse{} = response} =
        Operations.v2_search_get(name: "Bank", type: "business", limit: 5)

      for entity <- response.entities || [] do
        assert entity.entityType in ["business", nil]
      end
    end

    test "includes person details for person entities" do
      {:ok, %SearchResponse{} = response} =
        Operations.v2_search_get(name: "Putin", type: "person", limit: 1)

      [entity | _] = response.entities
      assert entity.entityType == "person"
      assert %Person{} = entity.person
      assert entity.person.name =~ "PUTIN"
    end

    test "includes address details when available" do
      {:ok, %SearchResponse{} = response} =
        Operations.v2_search_get(name: "Putin", limit: 1)

      [entity | _] = response.entities

      if entity.addresses && length(entity.addresses) > 0 do
        [address | _] = entity.addresses
        assert %Address{} = address
        assert is_binary(address.country) or is_nil(address.country)
      end
    end

    test "includes source data" do
      {:ok, %SearchResponse{} = response} =
        Operations.v2_search_get(name: "Putin", limit: 1)

      [entity | _] = response.entities
      assert is_map(entity.sourceData)
      assert Map.has_key?(entity.sourceData, "sdnName") or Map.has_key?(entity.sourceData, "entityID")
    end
  end

  describe "v2_listinfo_get/0" do
    test "returns list information" do
      {:ok, %ListInfoResponse{} = info} = Operations.v2_listinfo_get()

      assert is_map(info.lists)
      assert Map.has_key?(info.lists, "us_ofac")
      assert Map.has_key?(info.lists, "us_csl")
      assert info.lists["us_ofac"] > 10_000
    end

    test "returns version information" do
      {:ok, %ListInfoResponse{} = info} = Operations.v2_listinfo_get()

      assert is_binary(info.version)
    end

    test "returns list hashes" do
      {:ok, %ListInfoResponse{} = info} = Operations.v2_listinfo_get()

      assert is_map(info.listHashes) or is_nil(info.listHashes)
    end
  end
end
