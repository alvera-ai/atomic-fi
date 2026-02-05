defmodule PaymentCompliancePlatform.Watchman.OperationsTest do
  use ExUnit.Case, async: true

  alias PaymentCompliancePlatform.Watchman.{
    Address,
    Entity,
    ListInfoResponse,
    Operations,
    Person,
    SearchResponse
  }

  # Real API response captured from: curl "http://localhost:8084/v2/search?name=Putin&limit=2"
  @search_response %{
    "query" => %{
      "name" => "Putin",
      "entityType" => "",
      "sourceList" => "api-request"
    },
    "entities" => [
      %{
        "name" => "Vladimir Vladimirovich PUTIN",
        "entityType" => "person",
        "sourceList" => "us_ofac",
        "sourceID" => "35096",
        "person" => %{
          "name" => "Vladimir Vladimirovich PUTIN",
          "altNames" => ["Vladimir PUTIN"],
          "gender" => "male",
          "birthDate" => "1952-10-07T00:00:00Z",
          "titles" => ["President of the Russian Federation"]
        },
        "addresses" => [
          %{
            "line1" => "Kremlin",
            "city" => "Moscow",
            "country" => "Russia"
          }
        ],
        "contact" => %{
          "emailAddresses" => nil,
          "phoneNumbers" => nil
        },
        "sourceData" => %{
          "entityID" => "35096",
          "sdnName" => "PUTIN, Vladimir Vladimirovich",
          "sdnType" => "individual",
          "program" => ["RUSSIA-EO14024"],
          "title" => "President of the Russian Federation"
        },
        "match" => 0.7372730769230769
      },
      %{
        "name" => "Pu Ung YU",
        "entityType" => "person",
        "sourceList" => "us_ofac",
        "sourceID" => "47701",
        "person" => %{
          "name" => "Pu Ung YU",
          "altNames" => ["Mr. O", "Bu Ung YU"],
          "gender" => "male"
        },
        "addresses" => [
          %{
            "line1" => "67 Kap 2-9-1",
            "city" => "Shenyang",
            "country" => "China"
          }
        ],
        "sourceData" => %{
          "entityID" => "47701",
          "sdnName" => "YU, Pu Ung"
        },
        "match" => 0.6115855714285715
      }
    ]
  }

  # Real API response captured from: curl "http://localhost:8084/v2/listinfo"
  @listinfo_response %{
    "lists" => %{
      "us_csl" => 6682,
      "us_fincen_311" => 35,
      "us_non_sdn" => 442,
      "us_ofac" => 18598
    },
    "listHashes" => %{
      "us_csl" => "a9bf801038466302bfecc214e79bc34d219d04f2a7d9d83a6e99992a6e2c7ba7",
      "us_ofac" => "f4317a3e3129afd8d42e1acd034555c9ed41f39aa118f2cc1cb93d1185a7cbe9"
    },
    "startedAt" => "2026-02-05T15:44:07.630831419Z",
    "endedAt" => "2026-02-05T15:44:40.400128795Z",
    "version" => "0.1.0"
  }

  @empty_search_response %{
    "query" => %{"name" => "xyznonexistent"},
    "entities" => []
  }

  setup do
    # Use Req's test plug to mock responses
    Req.Test.stub(PaymentCompliancePlatform.Watchman.Client, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/v2/search"} ->
          query = URI.decode_query(conn.query_string)

          response =
            if query["name"] =~ "nonexistent" do
              @empty_search_response
            else
              @search_response
            end

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(response))

        {"GET", "/v2/listinfo"} ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(@listinfo_response))

        _ ->
          Plug.Conn.send_resp(conn, 404, "Not Found")
      end
    end)

    :ok
  end

  describe "v2_search_get/1" do
    test "returns matching entities for a known sanctioned person" do
      {:ok, %SearchResponse{} = response} = Operations.v2_search_get(name: "Putin")

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
        Operations.v2_search_get(name: "xyznonexistent12345")

      assert response.entities == []
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
      assert length(entity.addresses) >= 1

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
      assert info.lists["us_ofac"] == 18598
      assert info.lists["us_csl"] == 6682
      assert info.lists["us_fincen_311"] == 35
    end

    test "returns version information" do
      {:ok, %ListInfoResponse{} = info} = Operations.v2_listinfo_get()

      assert info.version == "0.1.0"
    end

    test "returns list hashes" do
      {:ok, %ListInfoResponse{} = info} = Operations.v2_listinfo_get()

      assert is_map(info.listHashes)

      assert info.listHashes["us_ofac"] ==
               "f4317a3e3129afd8d42e1acd034555c9ed41f39aa118f2cc1cb93d1185a7cbe9"
    end
  end
end
