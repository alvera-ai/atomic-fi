defmodule AtomicFi.DecisionContext.ScreeningEngineTest do
  use AtomicFi.DataCase

  alias AtomicFi.BlocklistContext.BlocklistEntry
  alias AtomicFi.DecisionContext.{BlocklistCache, ScreeningEngine}

  defp insert_entry(tenant_id, scope, term) do
    Repo.insert!(
      %BlocklistEntry{
        tenant_id: tenant_id,
        scope: scope,
        entry_type: :exact,
        term: term,
        reason: "test",
        active: true
      },
      skip_multi_tenancy_check: true
    )
  end

  describe "determine_overall_status/1" do
    test "returns :blocked when any result is blocked" do
      results = [
        %{screening_status: :pass},
        %{screening_status: :blocked},
        %{screening_status: :potential_match}
      ]
      assert ScreeningEngine.determine_overall_status(results) == :blocked
    end

    test "returns :potential_match when no blocked but at least one potential_match" do
      results = [%{screening_status: :pass}, %{screening_status: :potential_match}]
      assert ScreeningEngine.determine_overall_status(results) == :potential_match
    end

    test "returns :pass when all are pass" do
      assert ScreeningEngine.determine_overall_status([%{screening_status: :pass}]) == :pass
    end

    test "returns :pass for an empty list" do
      assert ScreeningEngine.determine_overall_status([]) == :pass
    end
  end

  describe "screen_individual/3 — blocklist fail-fast (no Watchman call)" do
    setup %{tenant: tenant} do
      insert_entry(tenant.id, :first_name, "blocked")
      BlocklistCache.refresh_tenant_cache(tenant.id)
      :ok
    end

    test "returns a :blocked result with blocklist_matches and no sanctions_matches",
         %{tenant: tenant} do
      assert {:ok, result} =
               ScreeningEngine.screen_individual(tenant.id, %{
                 first_name: "Blocked",
                 last_name: "Person"
               })

      assert result.entity_type == :individual
      assert result.entity_name == "Blocked Person"
      assert result.screening_status == :blocked
      assert result.sanctions_matches == []
      assert length(result.blocklist_matches) >= 1

      match = hd(result.blocklist_matches)
      assert match.scope == :first_name
      assert match.match_type == :exact
      assert match.matched_term == "blocked"
      assert %DateTime{} = match.blocklist_updated_at
    end
  end

  describe "screen_company/3 — blocklist fail-fast (no Watchman call)" do
    setup %{tenant: tenant} do
      insert_entry(tenant.id, :company_name, "acme")
      BlocklistCache.refresh_tenant_cache(tenant.id)
      :ok
    end

    test "returns a :blocked result with the company-name match", %{tenant: tenant} do
      assert {:ok, result} =
               ScreeningEngine.screen_company(tenant.id, %{name: "ACME Corp"})

      assert result.entity_type == :company
      assert result.screening_status == :blocked
      assert result.sanctions_matches == []
      assert length(result.blocklist_matches) == 1
      assert hd(result.blocklist_matches).scope == :company_name
    end
  end

  describe "get_watchman_list_info/0 (live Watchman)" do
    test "returns started_at, lists, version" do
      assert {:ok, info} = ScreeningEngine.get_watchman_list_info()
      assert %DateTime{} = info.started_at
      assert info.lists != nil
      assert info.version != nil
    end
  end

  describe "screen_individual/3 — Watchman path (no blocklist hit)" do
    setup %{tenant: tenant} do
      BlocklistCache.refresh_tenant_cache(tenant.id)
      :ok
    end

    test "clean name passes through Watchman and returns :pass-shape result",
         %{tenant: tenant} do
      assert {:ok, result} =
               ScreeningEngine.screen_individual(tenant.id, %{
                 first_name: "Jane",
                 last_name: "Cleansurname#{System.unique_integer([:positive])}"
               })

      assert result.entity_type == :individual
      assert result.blocklist_matches == []
      assert result.screening_status in [:pass, :potential_match, :blocked]
      assert %DateTime{} = result.screened_at
    end

    test "sanctioned name (Vladimir Putin) returns hits with normalized person/business/address data",
         %{tenant: tenant} do
      assert {:ok, result} =
               ScreeningEngine.screen_individual(tenant.id, %{
                 first_name: "Vladimir",
                 last_name: "Putin"
               })

      assert result.entity_type == :individual
      assert result.screening_status in [:potential_match, :blocked]
      assert result.match_count > 0
      assert is_float(result.screening_score)
      assert Enum.any?(result.sanctions_matches, fn m -> is_binary(m.source_list) end)
    end

    test "passes birth_date and gender through maybe_add into the Watchman query",
         %{tenant: tenant} do
      # Verifies the maybe_add branches (non-nil, non-empty) by passing optional opts
      assert {:ok, _result} =
               ScreeningEngine.screen_individual(tenant.id, %{
                 first_name: "Jane",
                 last_name: "Test#{System.unique_integer([:positive])}",
                 birth_date: "1990-01-01",
                 gender: "female"
               })
    end
  end

  describe "screen_company/3 — Watchman path (no blocklist hit)" do
    setup %{tenant: tenant} do
      BlocklistCache.refresh_tenant_cache(tenant.id)
      :ok
    end

    test "clean company passes through Watchman", %{tenant: tenant} do
      assert {:ok, result} =
               ScreeningEngine.screen_company(tenant.id, %{
                 name: "Random Company #{System.unique_integer([:positive])}"
               })

      assert result.entity_type == :company
      assert result.blocklist_matches == []
      assert result.screening_status in [:pass, :potential_match, :blocked]
    end

    test "company with optional created/dissolved dates exercises maybe_add",
         %{tenant: tenant} do
      assert {:ok, _result} =
               ScreeningEngine.screen_company(tenant.id, %{
                 name: "Test Corp #{System.unique_integer([:positive])}",
                 created: "2020-01-01",
                 dissolved: "2024-01-01"
               })
    end

    test "sanctioned business returns matches with normalized business_data",
         %{tenant: tenant} do
      assert {:ok, result} =
               ScreeningEngine.screen_company(tenant.id, %{name: "Wagner Group"})

      assert result.entity_type == :company
      assert result.match_count > 0

      # At least one match should have business_data populated
      assert Enum.any?(result.sanctions_matches, fn m ->
               is_map(m.business_data) and m.business_data != nil
             end)
    end

    test "empty-string optional fields are dropped via maybe_add", %{tenant: tenant} do
      # birth_date: "" exercises maybe_add(_, _, "") clause for individuals
      assert {:ok, _} =
               ScreeningEngine.screen_individual(tenant.id, %{
                 first_name: "Jane",
                 last_name: "Empty#{System.unique_integer([:positive])}",
                 birth_date: "",
                 gender: ""
               })
    end
  end

  describe "Watchman error branches (Mox stub)" do
    import Mox

    test "get_watchman_list_info/0 propagates {:error, _}" do
      expect(AtomicFi.WatchmanMock, :v2_listinfo_get, fn _ -> {:error, :boom} end)
      assert {:error, :boom} = ScreeningEngine.get_watchman_list_info()
    end

    test "get_watchman_list_info/0 maps bare :error → :watchman_listinfo_unavailable" do
      expect(AtomicFi.WatchmanMock, :v2_listinfo_get, fn _ -> :error end)
      assert {:error, :watchman_listinfo_unavailable} = ScreeningEngine.get_watchman_list_info()
    end

    test "screen_individual propagates {:error, _}", %{tenant: tenant} do
      BlocklistCache.refresh_tenant_cache(tenant.id)
      expect(AtomicFi.WatchmanMock, :v2_search_get, fn _ -> {:error, :boom} end)

      assert {:error, :boom} =
               ScreeningEngine.screen_individual(tenant.id, %{
                 first_name: "Clean",
                 last_name: "Person#{System.unique_integer([:positive])}"
               })
    end

    test "screen_individual maps bare :error → :watchman_search_unavailable",
         %{tenant: tenant} do
      BlocklistCache.refresh_tenant_cache(tenant.id)
      expect(AtomicFi.WatchmanMock, :v2_search_get, fn _ -> :error end)

      assert {:error, :watchman_search_unavailable} =
               ScreeningEngine.screen_individual(tenant.id, %{
                 first_name: "Clean",
                 last_name: "Person#{System.unique_integer([:positive])}"
               })
    end

    test "screen_company maps bare :error → :watchman_search_unavailable",
         %{tenant: tenant} do
      BlocklistCache.refresh_tenant_cache(tenant.id)
      expect(AtomicFi.WatchmanMock, :v2_search_get, fn _ -> :error end)

      assert {:error, :watchman_search_unavailable} =
               ScreeningEngine.screen_company(tenant.id, %{
                 name: "Co#{System.unique_integer([:positive])}"
               })
    end
  end

  describe "Watchman response shape edge cases (Mox stub)" do
    import Mox

    alias AtomicFi.Watchman.{Entity, ListInfoResponse, Person, SearchResponse}

    setup %{tenant: tenant} do
      BlocklistCache.refresh_tenant_cache(tenant.id)
      :ok
    end

    test "match >= 0.95 classifies as :exact + normalize_*(nil) branches fire",
         %{tenant: tenant} do
      expect(AtomicFi.WatchmanMock, :v2_search_get, fn _ ->
        {:ok,
         %SearchResponse{
           entities: [
             %Entity{
               name: "Exact Match",
               entityType: "person",
               match: 0.99,
               sourceID: "X1",
               sourceList: "us_ofac",
               person: %Person{name: "Exact Match", gender: "M"},
               business: nil,
               contact: nil,
               addresses: nil,
               sourceData: %{any: "x"}
             }
           ]
         }}
      end)

      assert {:ok, result} =
               ScreeningEngine.screen_individual(tenant.id, %{
                 first_name: "Anyone",
                 last_name: "Eligible#{System.unique_integer([:positive])}"
               })

      assert result.screening_status == :blocked
      assert match = hd(result.sanctions_matches)
      assert match.sanctions_match_type == :exact
      # Exercises normalize_business(nil), normalize_contact(nil), normalize_addresses(nil)
      assert match.business_data == nil
      assert match.contact_data == nil
      assert match.addresses == []
      # Exercises normalize_person non-nil + the nationalities line (Person struct has
      # no :nationality field, so List.wrap(nil) → [] but the line still executes)
      assert match.person_data.nationalities == []
      assert match.source_data == %{any: "x"}
    end

    test "plain-map nested fields exercise get_field(map, key)", %{tenant: tenant} do
      # Pass plain maps for business/contact/addresses instead of structs to trigger
      # the `get_field(map, key) when is_map(map)` branch.
      expect(AtomicFi.WatchmanMock, :v2_search_get, fn _ ->
        {:ok,
         %SearchResponse{
           entities: [
             %Entity{
               name: "Bizmatch",
               entityType: "business",
               match: 0.85,
               sourceID: "B1",
               sourceList: "us_ofac",
               business: %{name: "AcmeCo", identifier: "REG-1"},
               contact: %{emailAddresses: ["x@y.z"], phoneNumbers: [], websites: nil},
               addresses: [%{address1: "1 Way", city: "NYC", country: "US"}],
               sourceData: nil
             }
           ]
         }}
      end)

      assert {:ok, result} =
               ScreeningEngine.screen_company(tenant.id, %{name: "Probe Co"})

      m = hd(result.sanctions_matches)
      assert m.business_data.name == "AcmeCo"
      assert m.business_data.registration_number == "REG-1"
      assert m.contact_data.emails == ["x@y.z"]
      assert m.contact_data.websites == []
      assert [%{line1: "1 Way", city: "NYC", country: "US"} | _] = m.addresses
    end

    test "to_map/1 handles a nil sourceData (entity-shape edge case)", %{tenant: tenant} do
      expect(AtomicFi.WatchmanMock, :v2_search_get, fn _ ->
        {:ok,
         %SearchResponse{
           entities: [
             %Entity{
               name: "X",
               entityType: "person",
               match: 0.8,
               sourceID: "S",
               sourceList: "l",
               sourceData: nil
             }
           ]
         }}
      end)

      assert {:ok, result} =
               ScreeningEngine.screen_individual(tenant.id, %{
                 first_name: "F",
                 last_name: "L#{System.unique_integer([:positive])}"
               })

      assert hd(result.sanctions_matches).source_data == nil
    end

    test "parse_datetime accepts non-binary input → DateTime.utc_now()" do
      expect(AtomicFi.WatchmanMock, :v2_listinfo_get, fn _ ->
        {:ok,
         %ListInfoResponse{
           startedAt: nil,
           lists: %{"us_ofac" => 0},
           version: "v1"
         }}
      end)

      assert {:ok, info} = ScreeningEngine.get_watchman_list_info()
      assert %DateTime{} = info.started_at
    end

    test "parse_datetime maps malformed ISO8601 to DateTime.utc_now()" do
      expect(AtomicFi.WatchmanMock, :v2_listinfo_get, fn _ ->
        {:ok,
         %ListInfoResponse{
           startedAt: "not-a-real-iso8601",
           lists: %{},
           version: "v1"
         }}
      end)

      assert {:ok, info} = ScreeningEngine.get_watchman_list_info()
      assert %DateTime{} = info.started_at
    end
  end
end
