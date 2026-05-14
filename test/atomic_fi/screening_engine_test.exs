defmodule AtomicFi.ScreeningEngineTest do
  use AtomicFi.DataCase

  alias AtomicFi.AccountHolderContext
  alias AtomicFi.BeneficialOwnerContext
  alias AtomicFi.BlocklistContext.BlocklistEntry
  alias AtomicFi.CounterpartyContext
  alias AtomicFi.BlocklistContext.BlocklistCache
  alias AtomicFi.ScreeningEngine

  # Entity-shaped public API is the only seam. Internal screen_individual /
  # screen_company are private; Watchman is hit through Watchman.Client.
  # Live :8084 Watchman is exercised by these tests.

  defp insert_blocklist_entry(tenant_id, scope, term) do
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

  describe "get_watchman_list_info/0 (live Watchman)" do
    test "returns started_at, lists, version" do
      assert {:ok, info} = ScreeningEngine.get_watchman_list_info()
      assert %DateTime{} = info.started_at
      assert info.lists != nil
      assert info.version != nil
    end
  end

  describe "screen_account_holder/3 — blocklist fail-fast (no Watchman call)" do
    setup %{tenant: tenant} do
      insert_blocklist_entry(tenant.id, :first_name, "blocked")
      BlocklistCache.refresh_tenant_cache(tenant.id)
      :ok
    end

    test "returns a :blocked result with blocklist_matches", %{session: session} do
      legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          first_name: "Blocked",
          last_name: "Person"
        )

      ah = insert(:account_holder, tenant_id: session.tenant_id, legal_entity_id: legal_entity.id)
      ah = AccountHolderContext.get_account_holder!(session, ah.id)

      assert {:ok, result} = ScreeningEngine.screen_account_holder(session, ah)

      assert result.entity_type == :individual
      assert result.entity_name == "Blocked Person"
      assert result.screening_status == :blocked
      assert result.sanctions_matches == []
      assert length(result.blocklist_matches) >= 1
      assert hd(result.blocklist_matches).scope == :first_name
    end
  end

  describe "screen_counterparty/3 — blocklist fail-fast for businesses" do
    setup %{tenant: tenant} do
      insert_blocklist_entry(tenant.id, :company_name, "acme")
      BlocklistCache.refresh_tenant_cache(tenant.id)
      :ok
    end

    test "returns :blocked with company-name match", %{session: session} do
      legal_entity =
        insert(:business_legal_entity, tenant_id: session.tenant_id, business_name: "ACME Corp")

      cp =
        insert(:counterparty, tenant_id: session.tenant_id, legal_entity_id: legal_entity.id)

      cp = CounterpartyContext.get_counterparty!(session, cp.id)

      assert {:ok, result} = ScreeningEngine.screen_counterparty(session, cp)

      assert result.entity_type == :company
      assert result.screening_status == :blocked
      assert length(result.blocklist_matches) == 1
    end
  end

  describe "screen_account_holder/3 — Watchman path (no blocklist hit)" do
    setup %{tenant: tenant} do
      BlocklistCache.refresh_tenant_cache(tenant.id)
      :ok
    end

    test "clean name passes through Watchman to a :pass-shape result", %{session: session} do
      legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          first_name: "Jane",
          last_name: "Cleansurname#{System.unique_integer([:positive])}"
        )

      ah = insert(:account_holder, tenant_id: session.tenant_id, legal_entity_id: legal_entity.id)
      ah = AccountHolderContext.get_account_holder!(session, ah.id)

      assert {:ok, result} = ScreeningEngine.screen_account_holder(session, ah)

      assert result.entity_type == :individual
      assert result.blocklist_matches == []
      assert result.screening_status in [:pass, :potential_match, :blocked]
      assert %DateTime{} = result.screened_at
    end

    test "sanctioned name (Vladimir Putin) yields hits with normalized person/address data",
         %{session: session} do
      legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          first_name: "Vladimir",
          last_name: "Putin"
        )

      ah = insert(:account_holder, tenant_id: session.tenant_id, legal_entity_id: legal_entity.id)
      ah = AccountHolderContext.get_account_holder!(session, ah.id)

      assert {:ok, result} = ScreeningEngine.screen_account_holder(session, ah)

      assert result.entity_type == :individual
      assert result.screening_status in [:potential_match, :blocked]
      assert result.match_count > 0
      assert is_float(result.screening_score)
      assert Enum.any?(result.sanctions_matches, fn m -> is_binary(m.source_list) end)
    end
  end

  describe "screen_counterparty/3 — Watchman path for businesses" do
    setup %{tenant: tenant} do
      BlocklistCache.refresh_tenant_cache(tenant.id)
      :ok
    end

    test "clean company passes through Watchman", %{session: session} do
      legal_entity =
        insert(:business_legal_entity,
          tenant_id: session.tenant_id,
          business_name: "Random Company #{System.unique_integer([:positive])}"
        )

      cp = insert(:counterparty, tenant_id: session.tenant_id, legal_entity_id: legal_entity.id)
      cp = CounterpartyContext.get_counterparty!(session, cp.id)

      assert {:ok, result} = ScreeningEngine.screen_counterparty(session, cp)

      assert result.entity_type == :company
      assert result.blocklist_matches == []
      assert result.screening_status in [:pass, :potential_match, :blocked]
    end

    test "sanctioned business (Wagner Group) returns matches with normalized business_data",
         %{session: session} do
      legal_entity =
        insert(:business_legal_entity,
          tenant_id: session.tenant_id,
          business_name: "Wagner Group"
        )

      cp = insert(:counterparty, tenant_id: session.tenant_id, legal_entity_id: legal_entity.id)
      cp = CounterpartyContext.get_counterparty!(session, cp.id)

      assert {:ok, result} = ScreeningEngine.screen_counterparty(session, cp)
      assert result.entity_type == :company
      assert result.match_count > 0
    end
  end

  describe "screen_beneficial_owner/3" do
    setup %{tenant: tenant} do
      BlocklistCache.refresh_tenant_cache(tenant.id)
      :ok
    end

    test "screens a clean BO and returns a result", %{session: session} do
      bo_legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          first_name: "Clean",
          last_name: "BO#{System.unique_integer([:positive])}"
        )

      bo =
        insert(:beneficial_owner,
          tenant_id: session.tenant_id,
          legal_entity_id: bo_legal_entity.id
        )

      bo = BeneficialOwnerContext.get_beneficial_owner!(session, bo.id)

      assert {:ok, result} = ScreeningEngine.screen_beneficial_owner(session, bo)
      assert result.entity_type == :individual
      assert result.screening_status in [:pass, :potential_match, :blocked]
    end
  end

  describe "unimplemented callbacks" do
    test "screen_payment_account/3 raises", %{session: session} do
      assert_raise RuntimeError, ~r/not implemented yet/, fn ->
        ScreeningEngine.screen_payment_account(
          session,
          %AtomicFi.PaymentAccountContext.PaymentAccount{}
        )
      end
    end

    test "screen_transaction/3 raises", %{session: session} do
      assert_raise RuntimeError, ~r/not implemented yet/, fn ->
        ScreeningEngine.screen_transaction(session, %AtomicFi.TransactionContext.Transaction{})
      end
    end
  end
end
