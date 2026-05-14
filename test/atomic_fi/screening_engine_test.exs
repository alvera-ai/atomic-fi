defmodule AtomicFi.ScreeningEngineTest do
  use AtomicFi.DataCase

  alias AtomicFi.AccountHolderContext
  alias AtomicFi.BeneficialOwnerContext
  alias AtomicFi.BlocklistContext.BlocklistEntry
  alias AtomicFi.CounterpartyContext
  alias AtomicFi.BlocklistContext.BlocklistCache
  alias AtomicFi.ComplianceScreeningContext.ComplianceScreening
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  alias AtomicFi.ScreeningEngine

  # Engine returns unsaved %ComplianceScreening{} structs (id nil, tenant_id nil,
  # FKs nil — persistence is the caller's job). Status is always :pending; the
  # rule engine interprets the facts (matches + scores).

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

    test "returns a :pending result with blocklist_matches", %{session: session} do
      legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          first_name: "Blocked",
          last_name: "Person"
        )

      ah = insert(:account_holder, tenant_id: session.tenant_id, legal_entity_id: legal_entity.id)
      ah = AccountHolderContext.get_account_holder!(session, ah.id)

      assert {:ok, %ComplianceScreening{} = result} =
               ScreeningEngine.screen_account_holder(session, ah)

      assert is_nil(result.id)
      assert result.scope == :account_holder
      assert result.screening_type == :sanctions
      assert result.screening_status == :pending
      assert result.screened_entity_type == :individual
      assert result.screened_entity_name == "Blocked Person"
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

    test "returns :pending with company-name match", %{session: session} do
      legal_entity =
        insert(:business_legal_entity, tenant_id: session.tenant_id, business_name: "ACME Corp")

      cp =
        insert(:counterparty, tenant_id: session.tenant_id, legal_entity_id: legal_entity.id)

      cp = CounterpartyContext.get_counterparty!(session, cp.id)

      assert {:ok, %ComplianceScreening{} = result} =
               ScreeningEngine.screen_counterparty(session, cp)

      assert result.scope == :counterparty
      assert result.screened_entity_type == :company
      assert result.screening_status == :pending
      assert length(result.blocklist_matches) == 1
    end
  end

  describe "screen_account_holder/3 — Watchman path (no blocklist hit)" do
    setup %{tenant: tenant} do
      BlocklistCache.refresh_tenant_cache(tenant.id)
      :ok
    end

    test "clean name passes through Watchman with zero active matches",
         %{session: session} do
      legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          first_name: "Jane",
          last_name: "Cleansurname#{System.unique_integer([:positive])}"
        )

      ah = insert(:account_holder, tenant_id: session.tenant_id, legal_entity_id: legal_entity.id)
      ah = AccountHolderContext.get_account_holder!(session, ah.id)

      assert {:ok, %ComplianceScreening{} = result} =
               ScreeningEngine.screen_account_holder(session, ah)

      assert result.screened_entity_type == :individual
      assert result.blocklist_matches == []
      assert result.screening_status == :pending
      assert %DateTime{} = result.screened_at
    end

    test "sanctioned name (Vladimir Putin) yields hits with normalized person data",
         %{session: session} do
      legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          first_name: "Vladimir",
          last_name: "Putin"
        )

      ah = insert(:account_holder, tenant_id: session.tenant_id, legal_entity_id: legal_entity.id)
      ah = AccountHolderContext.get_account_holder!(session, ah.id)

      assert {:ok, %ComplianceScreening{} = result} =
               ScreeningEngine.screen_account_holder(session, ah)

      assert result.screened_entity_type == :individual
      assert result.screening_status == :pending
      assert result.match_count > 0
      assert %Decimal{} = result.screening_score
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

      assert {:ok, %ComplianceScreening{} = result} =
               ScreeningEngine.screen_counterparty(session, cp)

      assert result.screened_entity_type == :company
      assert result.blocklist_matches == []
      assert result.screening_status == :pending
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

      assert {:ok, %ComplianceScreening{} = result} =
               ScreeningEngine.screen_counterparty(session, cp)

      assert result.screened_entity_type == :company
      assert result.match_count > 0
    end
  end

  describe "screen_beneficial_owner/3" do
    setup %{tenant: tenant} do
      BlocklistCache.refresh_tenant_cache(tenant.id)
      :ok
    end

    test "screens a clean BO and returns a :pending result", %{session: session} do
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

      assert {:ok, %ComplianceScreening{} = result} =
               ScreeningEngine.screen_beneficial_owner(session, bo)

      assert result.scope == :beneficial_owner
      assert result.screened_entity_type == :individual
      assert result.screening_status == :pending
    end
  end

  describe "screen_payment_account/3 — crypto wallet path" do
    setup %{tenant: tenant} do
      BlocklistCache.refresh_tenant_cache(tenant.id)
      :ok
    end

    test "non-crypto PA returns a no-screen :pending result", %{session: session} do
      pa = %PaymentAccount{
        account_type: :bank_account,
        tenant_id: session.tenant_id
      }

      assert {:ok, %ComplianceScreening{} = result} =
               ScreeningEngine.screen_payment_account(session, pa)

      assert result.scope == :payment_account
      assert result.screened_entity_type == :payment_account
      assert result.screened_entity_name == "non-crypto-payment-account-bypass"
      assert result.screening_status == :pending
      assert result.match_count == 0
      assert result.sanctions_matches == []
    end

    test "crypto wallet hits Watchman with cryptoAddress search param",
         %{session: session} do
      pa = %PaymentAccount{
        account_type: :crypto_wallet,
        wallet_address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
        wallet_chain: "XBT",
        tenant_id: session.tenant_id
      }

      assert {:ok, %ComplianceScreening{} = result} =
               ScreeningEngine.screen_payment_account(session, pa)

      assert result.scope == :payment_account
      assert result.screened_entity_type == :crypto_address
      assert result.screening_status == :pending
    end
  end

  describe "unimplemented callbacks" do
    test "screen_transaction/3 raises", %{session: session} do
      assert_raise RuntimeError, ~r/not implemented yet/, fn ->
        ScreeningEngine.screen_transaction(session, %AtomicFi.TransactionContext.Transaction{})
      end
    end
  end
end
