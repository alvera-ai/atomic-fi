defmodule AtomicFi.Watchman.ClientTest do
  use ExUnit.Case, async: true

  alias AtomicFi.Watchman.{
    Address,
    Client,
    Entity,
    ListInfoResponse,
    Person,
    SearchResponse
  }

  # Tests run against the real Watchman service (http://localhost:8084).
  # Watchman is treated like postgres — defensive network/decode branches
  # use coveralls-ignore inside the production module rather than being
  # unit-tested here.

  describe "v2_search_get/1" do
    test "returns matching entities for a known sanctioned person" do
      {:ok, %SearchResponse{} = response} = Client.v2_search_get(name: "Putin", limit: 2)

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
        Client.v2_search_get(name: "xyznonexistent12345", minMatch: 0.7)

      assert response.entities in [nil, []]
    end

    test "includes person details for person entities" do
      {:ok, %SearchResponse{} = response} = Client.v2_search_get(name: "Putin")

      [entity | _] = response.entities
      assert entity.entityType == "person"
      assert %Person{} = entity.person
      assert entity.person.name == "Vladimir Vladimirovich PUTIN"
      assert entity.person.gender == "male"
      assert "Vladimir PUTIN" in entity.person.altNames
    end

    test "includes address details" do
      {:ok, %SearchResponse{} = response} = Client.v2_search_get(name: "Putin")

      [entity | _] = response.entities
      assert entity.addresses != []

      [address | _] = entity.addresses
      assert %Address{} = address
      assert address.line1 == "Kremlin"
      assert address.city == "Moscow"
      assert address.country == "Russia"
    end

    test "includes source data" do
      {:ok, %SearchResponse{} = response} = Client.v2_search_get(name: "Putin")

      [entity | _] = response.entities
      assert is_map(entity.sourceData)
      assert entity.sourceData["sdnName"] == "PUTIN, Vladimir Vladimirovich"
      assert entity.sourceData["entityID"] == "35096"
    end

    test "drops query keys not in the whitelist" do
      assert {:ok, %SearchResponse{}} =
               Client.v2_search_get(name: "Probe", not_a_real_key: "ignored")
    end
  end

  describe "v2_listinfo_get/0" do
    test "returns list information" do
      {:ok, %ListInfoResponse{} = info} = Client.v2_listinfo_get()

      assert is_map(info.lists)
      assert info.lists["us_ofac"] > 0
      assert info.lists["us_csl"] > 0
      assert info.lists["us_fincen_311"] > 0
    end

    test "returns version information" do
      {:ok, %ListInfoResponse{} = info} = Client.v2_listinfo_get()

      assert is_binary(info.version)
      assert String.match?(info.version, ~r/^v?\d+\.\d+\.\d+/)
    end

    test "returns list hashes" do
      {:ok, %ListInfoResponse{} = info} = Client.v2_listinfo_get()

      assert is_map(info.listHashes)
      assert is_binary(info.listHashes["us_ofac"])
      assert String.length(info.listHashes["us_ofac"]) == 64
      assert String.match?(info.listHashes["us_ofac"], ~r/^[a-f0-9]{64}$/)
    end
  end

  describe "v2_ingest_file_type_post/3" do
    test "returns an error tuple for an unknown ingest type (exercises ingest path)" do
      # Real Watchman returns 404 for /v2/ingest/<unknown>. Our decode_into
      # map only declares 200 → falls through to unexpected_status.
      assert {:error, _} = Client.v2_ingest_file_type_post("not-a-real-list", "garbage")
    end
  end
end
