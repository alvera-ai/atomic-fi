defmodule PaymentCompliancePlatformApi.OnboardingControllerTest do
  use PaymentCompliancePlatformWeb.ConnCase, async: true

  alias PaymentCompliancePlatformApi.ApiSpec

  describe "POST /api/onboarding/screen" do
    setup :setup_platform_admin_api

    test "screens account holder with clean individuals and companies", %{conn: conn} do
      init_blocklist_cache()

      request_body = %{
        name: "Clean Company LLC",
        type: "business",
        interested_individuals: [
          %{
            first_name: "Alice",
            last_name: "Wonderland"
          }
        ],
        interested_companies: [
          %{
            name: "Apple Inc"
          }
        ]
      }

      conn = post(conn, ~p"/api/onboarding/screen", request_body)

      assert %{
               "overall_status" => "pass",
               "total_entities_screened" => 2,
               "entities_with_matches" => 0,
               "entity_decisions" => entity_decisions
             } = json_response(conn, 200)

      assert length(entity_decisions) == 2

      alice = Enum.find(entity_decisions, fn ed -> ed["entity_name"] == "Alice Wonderland" end)
      assert alice["screening_result"] == "pass"
      assert alice["match_count"] == 0

      apple = Enum.find(entity_decisions, fn ed -> ed["entity_name"] == "Apple Inc" end)
      assert apple["screening_result"] == "pass"
      assert apple["match_count"] == 0
    end

    test "screens account holder with sanctioned individual", %{conn: conn} do
      init_blocklist_cache()

      request_body = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "Vladimir",
            last_name: "Putin",
            birth_date: "1952-10-07",
            gender: "male"
          }
        ],
        interested_companies: []
      }

      conn = post(conn, ~p"/api/onboarding/screen", request_body)

      assert %{
               "overall_status" => status,
               "total_entities_screened" => 1,
               "entities_with_matches" => 1,
               "entity_decisions" => [entity_decision]
             } = json_response(conn, 200)

      assert status in ["potential_match", "blocked"]
      assert entity_decision["entity_name"] == "Vladimir Putin"
      assert entity_decision["screening_result"] in ["potential_match", "blocked"]
      assert entity_decision["match_count"] > 0
      assert entity_decision["highest_match_score"] >= 0.7
      assert is_list(entity_decision["sanctions_matches"])
      assert entity_decision["sanctions_matches"] != []

      match = hd(entity_decision["sanctions_matches"])
      assert match["matched_name"]
      assert match["match_score"] >= 0.7
      assert match["source_list"]
    end

    test "screens account holder with sanctioned company", %{conn: conn} do
      init_blocklist_cache()

      request_body = %{
        name: "Partner Screening",
        type: "business",
        interested_individuals: [],
        interested_companies: [
          %{
            name: "Rosneft"
          }
        ]
      }

      conn = post(conn, ~p"/api/onboarding/screen", request_body)

      assert %{
               "overall_status" => status,
               "total_entities_screened" => 1,
               "entities_with_matches" => 1,
               "entity_decisions" => [entity_decision]
             } = json_response(conn, 200)

      assert status in ["potential_match", "blocked"]
      assert entity_decision["entity_name"] == "Rosneft"
      assert entity_decision["screening_result"] in ["potential_match", "blocked"]
      assert entity_decision["match_count"] > 0
    end

    test "screens mixed - clean and sanctioned entities", %{conn: conn} do
      init_blocklist_cache()

      request_body = %{
        name: "Mixed Screening Test",
        type: "business",
        interested_individuals: [
          %{
            first_name: "Alice",
            last_name: "Wonderland"
          },
          %{
            first_name: "Bashar",
            last_name: "al-Assad"
          }
        ],
        interested_companies: [
          %{
            name: "Microsoft Corporation"
          }
        ]
      }

      conn = post(conn, ~p"/api/onboarding/screen", request_body)

      assert %{
               "overall_status" => overall_status,
               "total_entities_screened" => 3,
               "entity_decisions" => entity_decisions
             } = json_response(conn, 200)

      # Overall should be blocked/potential_match if any entity matches
      assert overall_status in ["potential_match", "blocked"]
      assert length(entity_decisions) == 3

      alice = Enum.find(entity_decisions, fn ed -> ed["entity_name"] == "Alice Wonderland" end)
      assert alice["screening_result"] == "pass"

      assad =
        Enum.find(entity_decisions, fn ed -> String.contains?(ed["entity_name"], "Assad") end)

      assert assad["screening_result"] in ["potential_match", "blocked"]

      microsoft =
        Enum.find(entity_decisions, fn ed -> String.contains?(ed["entity_name"], "Microsoft") end)

      assert microsoft["screening_result"] == "pass"
    end

    test "screens famous athlete (clean)", %{conn: conn} do
      init_blocklist_cache()

      request_body = %{
        name: "Sports Agency",
        type: "business",
        interested_individuals: [
          %{
            first_name: "Lionel",
            last_name: "Messi"
          }
        ],
        interested_companies: []
      }

      conn = post(conn, ~p"/api/onboarding/screen", request_body)

      assert %{
               "overall_status" => "pass",
               "total_entities_screened" => 1,
               "entities_with_matches" => 0,
               "entity_decisions" => [entity_decision]
             } = json_response(conn, 200)

      assert entity_decision["entity_name"] == "Lionel Messi"
      assert entity_decision["screening_result"] == "pass"
      assert entity_decision["match_count"] == 0
    end

    test "accepts empty screening request", %{conn: conn} do
      request_body = %{
        interested_individuals: [],
        interested_companies: []
      }

      conn = post(conn, ~p"/api/onboarding/screen", request_body)

      assert %{"overall_status" => "pass"} = json_response(conn, 200)
    end

    test "returns validation error for individual with invalid structure", %{conn: conn} do
      request_body = %{
        interested_individuals: [
          %{
            # missing required last_name
            first_name: "John"
          }
        ],
        interested_companies: []
      }

      conn = post(conn, ~p"/api/onboarding/screen", request_body)

      assert %{"errors" => _errors} = json_response(conn, 422)
    end

    test "returns validation error for invalid individual structure (missing last_name)", %{
      conn: conn
    } do
      request_body = %{
        interested_individuals: [
          %{
            # Missing required last_name
            first_name: "John"
          }
        ],
        interested_companies: []
      }

      conn = post(conn, ~p"/api/onboarding/screen", request_body)

      assert %{"errors" => _errors} = json_response(conn, 422)
    end

    test "returns validation error for invalid company structure (missing name)", %{conn: conn} do
      request_body = %{
        interested_individuals: [],
        interested_companies: [
          %{
            # Missing required name
            created: "2020-01-01"
          }
        ]
      }

      conn = post(conn, ~p"/api/onboarding/screen", request_body)

      assert %{"errors" => _errors} = json_response(conn, 422)
    end

    test "includes list sync information in response", %{conn: conn} do
      init_blocklist_cache()

      request_body = %{
        name: "Info Test",
        type: "business",
        interested_individuals: [],
        interested_companies: []
      }

      conn = post(conn, ~p"/api/onboarding/screen", request_body)

      assert %{
               "list_synced_at" => list_synced_at,
               "list_sources" => list_sources
             } = json_response(conn, 200)

      assert list_synced_at
      assert is_map(list_sources)
      assert Map.has_key?(list_sources, "lists")
    end

    test "blocks individual with exact blocklisted first name", %{conn: conn} do
      seed_blocklist_for_platform_tenant()

      request_body = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "John",
            # "john" is in the blocklist
            last_name: "Zephyrwind"
            # Unique surname to avoid Watchman matches
          }
        ],
        interested_companies: []
      }

      conn = post(conn, ~p"/api/onboarding/screen", request_body)

      assert %{
               "overall_status" => "blocked",
               "total_entities_screened" => 1,
               "entities_with_matches" => 1,
               "entity_decisions" => [entity_decision]
             } = json_response(conn, 200)

      assert entity_decision["screening_result"] == "blocked"
      assert entity_decision["match_count"] == 0
      # No Watchman matches
      assert entity_decision["sanctions_matches"] == []
      # Has blocklist match
      assert entity_decision["blocklist_matches"] != []

      blocklist_match = hd(entity_decision["blocklist_matches"])
      assert blocklist_match["matched_term"] == "john"
      assert blocklist_match["match_type"] == "exact"
      assert blocklist_match["scope"] == "first_name"
      assert blocklist_match["blocklist_updated_at"] != nil
    end

    test "blocks individual with exact blocklisted last name", %{conn: conn} do
      seed_blocklist_for_platform_tenant()

      request_body = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "Zephyr",
            # Unique first name to avoid Watchman matches
            last_name: "Doe"
            # "doe" is in the blocklist
          }
        ],
        interested_companies: []
      }

      conn = post(conn, ~p"/api/onboarding/screen", request_body)

      assert %{
               "overall_status" => "blocked",
               "entity_decisions" => [entity_decision]
             } = json_response(conn, 200)

      assert entity_decision["screening_result"] == "blocked"
      assert entity_decision["blocklist_matches"] != []

      blocklist_match = hd(entity_decision["blocklist_matches"])
      assert blocklist_match["matched_term"] == "doe"
      assert blocklist_match["scope"] == "last_name"
    end

    test "blocks company with exact blocklisted name", %{conn: conn} do
      seed_blocklist_for_platform_tenant()

      request_body = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [],
        interested_companies: [
          %{
            name: "ACME Corporation"
            # "acme" is in the blocklist (normalized)
          }
        ]
      }

      conn = post(conn, ~p"/api/onboarding/screen", request_body)

      assert %{
               "overall_status" => "blocked",
               "entity_decisions" => [entity_decision]
             } = json_response(conn, 200)

      assert entity_decision["screening_result"] == "blocked"
      assert entity_decision["blocklist_matches"] != []

      blocklist_match = hd(entity_decision["blocklist_matches"])
      assert blocklist_match["matched_term"] == "acme"
      assert blocklist_match["scope"] == "company_name"
    end

    test "blocks individual with regex blocklisted first name", %{conn: conn} do
      seed_blocklist_for_platform_tenant()

      request_body = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "User123",
            # Matches "^user\d+$" regex pattern
            last_name: "Thunderstone"
            # Unique surname to avoid Watchman matches
          }
        ],
        interested_companies: []
      }

      conn = post(conn, ~p"/api/onboarding/screen", request_body)

      assert %{
               "overall_status" => "blocked",
               "entity_decisions" => [entity_decision]
             } = json_response(conn, 200)

      assert entity_decision["screening_result"] == "blocked"
      assert entity_decision["blocklist_matches"] != []

      blocklist_match = hd(entity_decision["blocklist_matches"])
      assert blocklist_match["match_type"] == "regex"
      assert blocklist_match["scope"] == "first_name"
    end

    test "blocks company with regex blocklisted name", %{conn: conn} do
      seed_blocklist_for_platform_tenant()

      request_body = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [],
        interested_companies: [
          %{
            name: "ZZZ Holdings"
            # Matches "^(zzz|xxx|aaa)\\s" regex pattern
          }
        ]
      }

      conn = post(conn, ~p"/api/onboarding/screen", request_body)

      assert %{
               "overall_status" => "blocked",
               "entity_decisions" => [entity_decision]
             } = json_response(conn, 200)

      assert entity_decision["screening_result"] == "blocked"
      assert entity_decision["blocklist_matches"] != []

      blocklist_match = hd(entity_decision["blocklist_matches"])
      assert blocklist_match["match_type"] == "regex"
      assert blocklist_match["scope"] == "company_name"
    end

    test "requires authentication", %{conn: base_conn} do
      # Remove API key
      conn = delete_req_header(base_conn, "x-api-key")

      request_body = %{
        name: "Test",
        type: "business",
        interested_individuals: [],
        interested_companies: []
      }

      conn = post(conn, ~p"/api/onboarding/screen", request_body)

      assert json_response(conn, 401)
    end
  end
end
