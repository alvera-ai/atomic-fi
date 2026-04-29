defmodule AtomicFi.Watchman.OperationsTest do
  use ExUnit.Case, async: true

  alias AtomicFi.Watchman.{
    Address,
    Entity,
    ListInfoResponse,
    Operations,
    Person,
    SearchResponse
  }

  # Tests run against real Watchman service (http://localhost:8084)
  # No mocks - we test the actual integration with the sanctions screening API

  describe "v2_search_get/1" do
    test "returns matching entities for a known sanctioned person" do
      {:ok, %SearchResponse{} = response} = Operations.v2_search_get(name: "Putin", limit: 2)

      assert is_list(response.entities)
      assert length(response.entities) == 2

      first = hd(response.entities)
      assert %Entity{} = first
      assert first.name == "Vladimir Vladimirovich PUTIN"
      assert first.entityType == "person"
      assert first.sourceList == "us_ofac"
      assert first.match == 0.7372730769230769
    end

    test "returns empty list for non-matching query" do
      {:ok, %SearchResponse{} = response} =
        Operations.v2_search_get(name: "xyznonexistent12345", minMatch: 0.7)

      assert response.entities in [nil, []]
    end

    test "includes person details for person entities" do
      {:ok, %SearchResponse{} = response} = Operations.v2_search_get(name: "Putin")

      [entity | _] = response.entities
      assert entity.entityType == "person"
      assert %Person{} = entity.person
      assert entity.person.name == "Vladimir Vladimirovich PUTIN"
      assert entity.person.gender == "male"
      assert "Vladimir PUTIN" in entity.person.altNames
    end

    test "includes address details" do
      {:ok, %SearchResponse{} = response} = Operations.v2_search_get(name: "Putin")

      [entity | _] = response.entities
      assert entity.addresses != []

      [address | _] = entity.addresses
      assert %Address{} = address
      assert address.line1 == "Kremlin"
      assert address.city == "Moscow"
      assert address.country == "Russia"
    end

    test "includes source data" do
      {:ok, %SearchResponse{} = response} = Operations.v2_search_get(name: "Putin")

      [entity | _] = response.entities
      assert is_map(entity.sourceData)
      assert entity.sourceData["sdnName"] == "PUTIN, Vladimir Vladimirovich"
      assert entity.sourceData["entityID"] == "35096"
    end
  end

  describe "v2_listinfo_get/0" do
    test "returns list information" do
      {:ok, %ListInfoResponse{} = info} = Operations.v2_listinfo_get()

      assert is_map(info.lists)
      # OFAC list counts change over time as sanctions are added/removed
      assert info.lists["us_ofac"] > 0
      assert info.lists["us_csl"] > 0
      assert info.lists["us_fincen_311"] > 0
    end

    test "returns version information" do
      {:ok, %ListInfoResponse{} = info} = Operations.v2_listinfo_get()

      # Watchman reports its own semver (e.g. "v0.61.1"); assert shape, not a
      # specific pin so upgrades don't break this test.
      assert is_binary(info.version)
      assert String.match?(info.version, ~r/^v?\d+\.\d+\.\d+/)
    end

    test "returns list hashes" do
      {:ok, %ListInfoResponse{} = info} = Operations.v2_listinfo_get()

      assert is_map(info.listHashes)
      # Hash changes when OFAC data updates - just verify it exists and looks like a SHA256 hash
      assert is_binary(info.listHashes["us_ofac"])
      assert String.length(info.listHashes["us_ofac"]) == 64
      assert String.match?(info.listHashes["us_ofac"], ~r/^[a-f0-9]{64}$/)
    end
  end
end
