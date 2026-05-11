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
end
