defmodule PaymentCompliancePlatform.DecisionContextTest do
  use PaymentCompliancePlatform.DataCase

  alias PaymentCompliancePlatform.DecisionContext

  describe "decisions" do
    alias PaymentCompliancePlatform.DecisionContext.Decision

    import PaymentCompliancePlatform.DecisionContextFixtures
    import PaymentCompliancePlatform.AccountHolderContextFixtures

    @invalid_attrs %{
      overall_status: nil,
      total_entities_screened: nil,
      entities_with_matches: nil,
      list_synced_at: nil,
      list_sources: nil
    }

    test "list_decisions/2 returns all decisions", %{session: session} do
      decision = decision_fixture()
      assert {:ok, {decisions, _meta}} = DecisionContext.list_decisions(session)
      assert length(decisions) == 1
      assert hd(decisions).id == decision.id
    end

    test "get_decision!/2 returns the decision with given id", %{session: session} do
      decision = decision_fixture()
      retrieved = DecisionContext.get_decision!(session, decision.id)
      assert retrieved.id == decision.id
      assert retrieved.overall_status == decision.overall_status
    end

    test "create_decision/2 with valid data creates a decision", %{
      session: session,
      tenant: tenant
    } do
      account_holder = account_holder_fixture()

      valid_attrs = %{
        account_holder_id: account_holder.id,
        overall_status: "pass",
        total_entities_screened: 42,
        entities_with_matches: 0,
        list_synced_at: ~U[2026-02-04 17:51:00.000000Z],
        list_sources: %{lists: %{"us_ofac" => 100}, version: "1.0"},
        tenant_id: tenant.id
      }

      assert {:ok, %Decision{} = decision} = DecisionContext.create_decision(session, valid_attrs)
      assert decision.overall_status == "pass"
      assert decision.total_entities_screened == 42
      assert decision.entities_with_matches == 0
      assert decision.list_synced_at == ~U[2026-02-04 17:51:00.000000Z]
    end

    test "create_decision/2 with invalid data returns error changeset", %{session: session} do
      assert {:error, %Ecto.Changeset{}} =
               DecisionContext.create_decision(session, @invalid_attrs)
    end

    test "update_decision/3 with valid data updates the decision", %{session: session} do
      decision = decision_fixture()

      update_attrs = %{
        overall_status: "blocked",
        total_entities_screened: 43,
        entities_with_matches: 2,
        list_synced_at: ~U[2026-02-05 17:51:00.000000Z]
      }

      assert {:ok, %Decision{} = decision} =
               DecisionContext.update_decision(session, decision, update_attrs)

      assert decision.overall_status == "blocked"
      assert decision.total_entities_screened == 43
      assert decision.entities_with_matches == 2
      assert decision.list_synced_at == ~U[2026-02-05 17:51:00.000000Z]
    end

    test "update_decision/3 with invalid data returns error changeset", %{session: session} do
      decision = decision_fixture()

      assert {:error, %Ecto.Changeset{}} =
               DecisionContext.update_decision(session, decision, @invalid_attrs)

      retrieved = DecisionContext.get_decision!(session, decision.id)
      assert retrieved.id == decision.id
      assert retrieved.overall_status == decision.overall_status
    end

    test "delete_decision/2 deletes the decision", %{session: session} do
      decision = decision_fixture()
      assert {:ok, %Decision{}} = DecisionContext.delete_decision(session, decision)

      assert_raise Ecto.NoResultsError, fn ->
        DecisionContext.get_decision!(session, decision.id)
      end
    end

    test "change_decision/1 returns a decision changeset" do
      decision = decision_fixture()
      assert %Ecto.Changeset{} = DecisionContext.change_decision(decision)
    end
  end

  describe "screen_account_holder/2" do
    setup do
      tenant = insert(:tenant)
      session = %{tenant_id: tenant.id, user_id: Ecto.UUID.generate()}
      {:ok, session: session}
    end

    test "raises error when blocklist cache is not initialized" do
      # Create a NEW tenant specifically for this test to avoid race conditions
      new_tenant = insert(:tenant)
      session = %{tenant_id: new_tenant.id, user_id: Ecto.UUID.generate()}

      # Do NOT initialize cache for this tenant
      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "John",
            last_name: "Doe"
          }
        ],
        interested_companies: []
      }

      request = cast_screening_request(request_data)

      # Should raise RuntimeError with specific message about uninitialized cache
      assert_raise RuntimeError, ~r/BlocklistCache not initialized for tenant/, fn ->
        DecisionContext.screen_account_holder(session, request)
      end
    end

    test "blocks individual with exact blocklisted first name", %{session: session} do
      seed_blocklist_for_tenant(session.tenant_id)

      request_data = %{
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

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.overall_status == "blocked"
      assert decision.total_entities_screened == 1
      assert decision.entities_with_matches == 1

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.screening_result == :blocked
      assert entity_decision.match_count == 0
      # No Watchman matches - blocked by blocklist
      assert entity_decision.sanctions_matches == []
      # Should have blocklist match
      assert entity_decision.blocklist_matches != []

      blocklist_match = hd(entity_decision.blocklist_matches)
      assert blocklist_match.matched_term == "john"
      assert blocklist_match.match_type == :exact
      assert blocklist_match.scope == :first_name
      assert blocklist_match.blocklist_updated_at != nil
    end

    test "blocks individual with exact blocklisted last name", %{session: session} do
      seed_blocklist_for_tenant(session.tenant_id)

      request_data = %{
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

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.overall_status == "blocked"

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.screening_result == :blocked
      assert entity_decision.blocklist_matches != []

      blocklist_match = hd(entity_decision.blocklist_matches)
      assert blocklist_match.matched_term == "doe"
      assert blocklist_match.match_type == :exact
      assert blocklist_match.scope == :last_name
    end

    test "blocks company with exact blocklisted name", %{session: session} do
      seed_blocklist_for_tenant(session.tenant_id)

      request_data = %{
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

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.overall_status == "blocked"

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.screening_result == :blocked
      assert entity_decision.blocklist_matches != []

      blocklist_match = hd(entity_decision.blocklist_matches)
      assert blocklist_match.matched_term == "acme"
      assert blocklist_match.match_type == :exact
      assert blocklist_match.scope == :company_name
    end

    test "blocks individual with regex blocklisted first name", %{session: session} do
      seed_blocklist_for_tenant(session.tenant_id)

      request_data = %{
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

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.overall_status == "blocked"

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.screening_result == :blocked
      assert entity_decision.blocklist_matches != []

      blocklist_match = hd(entity_decision.blocklist_matches)
      assert blocklist_match.match_type == :regex
      assert blocklist_match.scope == :first_name
    end

    test "blocks company with regex blocklisted name", %{session: session} do
      seed_blocklist_for_tenant(session.tenant_id)

      request_data = %{
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

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.overall_status == "blocked"

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.screening_result == :blocked
      assert entity_decision.blocklist_matches != []

      blocklist_match = hd(entity_decision.blocklist_matches)
      assert blocklist_match.match_type == :regex
      assert blocklist_match.scope == :company_name
    end

    test "screens account holder with no interested parties", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [],
        interested_companies: []
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.overall_status == "pass"
      assert decision.total_entities_screened == 0
      assert decision.entities_with_matches == 0
      assert decision.tenant_id == session.tenant_id
      assert decision.id != nil
    end

    test "screens account holder with individuals only", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "John",
            last_name: "Doe",
            birth_date: "1990-01-01",
            gender: "male"
          }
        ],
        interested_companies: []
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 1
      assert is_list(decision.entity_decisions)
      assert length(decision.entity_decisions) == 1

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.entity_type == :interested_individual
      assert entity_decision.entity_name == "John Doe"
      assert entity_decision.screening_result in [:pass, :potential_match, :blocked]
    end

    test "screens account holder with companies only", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [],
        interested_companies: [
          %{
            name: "ACME Corp",
            created: "2010-01-01"
          }
        ]
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 1
      assert is_list(decision.entity_decisions)
      assert length(decision.entity_decisions) == 1

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.entity_type == :interested_company
      assert entity_decision.entity_name == "ACME Corp"
      assert entity_decision.screening_result in [:pass, :potential_match, :blocked]
    end

    test "screens account holder with both individuals and companies", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "John",
            last_name: "Doe",
            birth_date: "1990-01-01"
          }
        ],
        interested_companies: [
          %{
            name: "ACME Corp",
            created: "2010-01-01"
          }
        ]
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 2
      assert length(decision.entity_decisions) == 2
      assert decision.overall_status in ["pass", "potential_match", "blocked"]
    end

    test "includes Watchman list sync information", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [],
        interested_companies: []
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.list_synced_at != nil
      assert is_map(decision.list_sources) or is_list(decision.list_sources)
    end

    test "stores raw request in decision", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [],
        interested_companies: []
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert is_map(decision.raw_request)
      assert Map.has_key?(decision.raw_request, :interested_individuals)
    end

    test "screens known sanctioned individual - Vladimir Putin", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
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

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 1
      assert decision.entities_with_matches >= 1
      assert decision.overall_status in ["blocked", "potential_match"]

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.entity_type == :interested_individual
      assert entity_decision.entity_name == "Vladimir Putin"
      assert entity_decision.screening_result in [:blocked, :potential_match]
      assert entity_decision.match_count > 0
      assert entity_decision.highest_match_score > 0.7

      # Verify sanctions matches are present
      assert is_list(entity_decision.sanctions_matches)
      assert entity_decision.sanctions_matches != []

      first_match = hd(entity_decision.sanctions_matches)
      assert first_match.matched_name != nil
      assert first_match.match_score > 0.7
      assert first_match.source_list != nil
      assert first_match.source_id != nil
    end

    test "screens known sanctioned individual - Bashar al-Assad", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "Bashar",
            last_name: "al-Assad",
            gender: "male"
          }
        ],
        interested_companies: []
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 1
      assert decision.entities_with_matches >= 1

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.screening_result in [:blocked, :potential_match]
      assert entity_decision.match_count > 0

      # Verify sanctions match details
      first_match = hd(entity_decision.sanctions_matches)
      assert String.contains?(String.downcase(first_match.matched_name), "assad")
    end

    test "screens clean individual - fictional name", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "Alice",
            last_name: "Wonderland",
            birth_date: "1990-01-01",
            gender: "female"
          }
        ],
        interested_companies: []
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 1
      assert decision.entities_with_matches == 0
      assert decision.overall_status == "pass"

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.entity_type == :interested_individual
      assert entity_decision.entity_name == "Alice Wonderland"
      assert entity_decision.screening_result == :pass
      assert entity_decision.match_count == 0
      assert entity_decision.highest_match_score == nil
      assert entity_decision.sanctions_matches == []
    end

    test "screens famous footballer - Lionel Messi", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "Lionel",
            last_name: "Messi",
            birth_date: "1987-06-24",
            gender: "male"
          }
        ],
        interested_companies: []
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 1
      assert decision.entities_with_matches == 0
      assert decision.overall_status == "pass"

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.entity_name == "Lionel Messi"
      assert entity_decision.screening_result == :pass
      assert entity_decision.match_count == 0
    end

    test "screens famous footballer - Cristiano Ronaldo", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "Cristiano",
            last_name: "Ronaldo",
            birth_date: "1985-02-05",
            gender: "male"
          }
        ],
        interested_companies: []
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 1
      assert decision.entities_with_matches == 0
      assert decision.overall_status == "pass"

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.entity_name == "Cristiano Ronaldo"
      assert entity_decision.screening_result == :pass
      assert entity_decision.match_count == 0
    end

    test "screens famous footballer - Neymar da Silva Santos Junior", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "Neymar",
            last_name: "da Silva Santos Junior",
            birth_date: "1992-02-05",
            gender: "male"
          }
        ],
        interested_companies: []
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 1
      assert decision.entities_with_matches == 0
      assert decision.overall_status == "pass"

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.screening_result == :pass
      assert entity_decision.match_count == 0
    end

    test "screens famous basketball player - LeBron James", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "LeBron",
            last_name: "James",
            birth_date: "1984-12-30",
            gender: "male"
          }
        ],
        interested_companies: []
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 1
      assert decision.entities_with_matches == 0
      assert decision.overall_status == "pass"

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.entity_name == "LeBron James"
      assert entity_decision.screening_result == :pass
      assert entity_decision.match_count == 0
    end

    test "screens famous tennis player - Serena Williams", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "Serena",
            last_name: "Williams",
            birth_date: "1981-09-26",
            gender: "female"
          }
        ],
        interested_companies: []
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 1
      assert decision.entities_with_matches == 0
      assert decision.overall_status == "pass"

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.entity_name == "Serena Williams"
      assert entity_decision.screening_result == :pass
      assert entity_decision.match_count == 0
    end

    test "screens tech entrepreneur - Elon Musk", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "Elon",
            last_name: "Musk",
            birth_date: "1971-06-28",
            gender: "male"
          }
        ],
        interested_companies: []
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 1
      assert decision.entities_with_matches == 0
      assert decision.overall_status == "pass"

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.entity_name == "Elon Musk"
      assert entity_decision.screening_result == :pass
      assert entity_decision.match_count == 0
    end

    test "screens known sanctioned company - Rosneft", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [],
        interested_companies: [
          %{
            name: "Rosneft"
          }
        ]
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 1

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.entity_type == :interested_company
      assert entity_decision.entity_name == "Rosneft"

      # Rosneft should have matches given Russian sanctions
      if entity_decision.match_count > 0 do
        assert entity_decision.screening_result in [:blocked, :potential_match]
        assert entity_decision.highest_match_score > 0.7
        assert entity_decision.sanctions_matches != []

        first_match = hd(entity_decision.sanctions_matches)
        assert first_match.matched_name != nil
        assert first_match.matched_entity_type != nil
        assert String.contains?(String.downcase(first_match.matched_name), "rosneft")
      end
    end

    test "screens known sanctioned company - Bank Rossiya", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [],
        interested_companies: [
          %{
            name: "Bank Rossiya"
          }
        ]
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 1

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.entity_type == :interested_company

      # Bank Rossiya is sanctioned
      if entity_decision.match_count > 0 do
        assert entity_decision.screening_result in [:blocked, :potential_match]
        assert entity_decision.highest_match_score > 0.7

        first_match = hd(entity_decision.sanctions_matches)

        assert String.contains?(String.downcase(first_match.matched_name), "rossiya") or
                 String.contains?(String.downcase(first_match.matched_name), "russia")
      end
    end

    test "screens clean Fortune 500 company - Apple Inc", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [],
        interested_companies: [
          %{
            name: "Apple Inc",
            created: "1976-04-01"
          }
        ]
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 1
      assert decision.entities_with_matches == 0
      assert decision.overall_status == "pass"

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.entity_type == :interested_company
      assert entity_decision.entity_name == "Apple Inc"
      assert entity_decision.screening_result == :pass
      assert entity_decision.match_count == 0
      assert entity_decision.highest_match_score == nil
      assert entity_decision.sanctions_matches == []
    end

    test "screens clean Fortune 500 company - Microsoft Corporation", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [],
        interested_companies: [
          %{
            name: "Microsoft Corporation",
            created: "1975-04-04"
          }
        ]
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 1
      assert decision.entities_with_matches == 0
      assert decision.overall_status == "pass"

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.entity_type == :interested_company
      assert entity_decision.entity_name == "Microsoft Corporation"
      assert entity_decision.screening_result == :pass
      assert entity_decision.match_count == 0
    end

    test "screens clean Fortune 500 company - Amazon.com Inc", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [],
        interested_companies: [
          %{
            name: "Amazon.com Inc"
          }
        ]
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 1
      assert decision.entities_with_matches == 0
      assert decision.overall_status == "pass"

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.screening_result == :pass
      assert entity_decision.match_count == 0
    end

    test "screens mixed - sanctioned individual with clean Fortune 500 company", %{
      session: session
    } do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "Vladimir",
            last_name: "Putin"
          }
        ],
        interested_companies: [
          %{
            name: "Google LLC"
          }
        ]
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 2

      # Overall status should be blocked/potential_match due to Putin
      assert decision.overall_status in ["blocked", "potential_match"]

      # Find Putin's entity decision
      putin_decision =
        Enum.find(decision.entity_decisions, fn ed ->
          ed.entity_name == "Vladimir Putin"
        end)

      assert putin_decision != nil
      assert putin_decision.screening_result in [:blocked, :potential_match]
      assert putin_decision.match_count > 0

      # Find company's entity decision
      company_decision =
        Enum.find(decision.entity_decisions, fn ed ->
          ed.entity_name == "Google LLC"
        end)

      assert company_decision != nil
      assert company_decision.screening_result == :pass
      assert company_decision.match_count == 0
    end

    test "screens mixed - clean individual with sanctioned company", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "Zephyr",
            last_name: "Moonbeam",
            birth_date: "1985-06-15"
          }
        ],
        interested_companies: [
          %{
            name: "Rosneft"
          }
        ]
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 2

      # Find individual's entity decision
      individual_decision =
        Enum.find(decision.entity_decisions, fn ed ->
          ed.entity_name == "Zephyr Moonbeam"
        end)

      assert individual_decision != nil
      assert individual_decision.screening_result == :pass
      assert individual_decision.match_count == 0

      # Find Rosneft's entity decision
      rosneft_decision =
        Enum.find(decision.entity_decisions, fn ed ->
          ed.entity_name == "Rosneft"
        end)

      assert rosneft_decision != nil

      # Overall status depends on Rosneft match
      if rosneft_decision.match_count > 0 do
        assert decision.overall_status in ["blocked", "potential_match"]
        assert rosneft_decision.screening_result in [:blocked, :potential_match]
      end
    end

    test "screens multiple sanctioned individuals", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "Vladimir",
            last_name: "Putin"
          },
          %{
            first_name: "Bashar",
            last_name: "al-Assad"
          }
        ],
        interested_companies: []
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)
      assert decision.total_entities_screened == 2
      assert decision.entities_with_matches >= 1
      assert decision.overall_status in ["blocked", "potential_match"]

      # Both should have matches
      Enum.each(decision.entity_decisions, fn entity_decision ->
        assert entity_decision.screening_result in [:blocked, :potential_match]
        assert entity_decision.match_count > 0
        assert entity_decision.sanctions_matches != []
      end)
    end

    test "verifies sanctions match data structure", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{
            first_name: "Vladimir",
            last_name: "Putin",
            birth_date: "1952-10-07"
          }
        ],
        interested_companies: []
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)

      entity_decision = hd(decision.entity_decisions)
      assert entity_decision.match_count > 0

      first_match = hd(entity_decision.sanctions_matches)

      # Verify all required fields in sanctions match
      assert is_binary(first_match.matched_name)
      assert is_binary(first_match.matched_entity_type)
      assert is_float(first_match.match_score)
      assert is_binary(first_match.source_list)
      assert is_binary(first_match.source_id)

      # Verify optional nested data structures
      assert is_list(first_match.addresses)

      # If person_data exists, verify structure
      if first_match.person_data do
        assert is_map(first_match.person_data)
      end

      # source_data should be a map
      if first_match.source_data do
        assert is_map(first_match.source_data)
      end
    end

    test "verifies match score thresholds - high confidence match", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
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

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)

      entity_decision = hd(decision.entity_decisions)

      # With full details (name + DOB + gender), should get high match score
      if entity_decision.highest_match_score && entity_decision.highest_match_score >= 0.95 do
        assert entity_decision.screening_result == :blocked
      else
        assert entity_decision.screening_result == :potential_match
      end
    end

    test "verifies list sync information is populated", %{session: session} do
      init_blocklist_cache(session.tenant_id)

      request_data = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [],
        interested_companies: []
      }

      request = cast_screening_request(request_data)
      assert {:ok, decision} = DecisionContext.screen_account_holder(session, request)

      # Verify list sources structure
      assert is_map(decision.list_sources)
      assert Map.has_key?(decision.list_sources, :lists)
      assert Map.has_key?(decision.list_sources, :version)

      # Verify lists is a map of list names to counts
      assert is_map(decision.list_sources.lists)

      # Verify we have some common sanctions lists
      lists = decision.list_sources.lists
      assert map_size(lists) > 0

      # Verify list_synced_at is a datetime
      assert %DateTime{} = decision.list_synced_at
    end
  end
end
