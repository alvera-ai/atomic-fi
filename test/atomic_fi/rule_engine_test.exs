defmodule AtomicFi.RuleEngineTest do
  use AtomicFi.DataCase, async: true

  alias AtomicFi.LegalEntityContext.LegalEntityAddress
  alias AtomicFi.Repo
  alias AtomicFi.RuleEngine
  alias AtomicFi.RuleEngine.Control
  alias AtomicFi.TransactionContext.Transaction

  # Mirrors TransactionContext.@rule_engine_preloads — the production txn flow
  # preloads this exact shape before handing the entity tree to the rule engine.
  # `las` and `compliance_screenings` are NOT preloaded — RuleEngine.build_payload
  # queries them fresh from each PA at build time (rule-engine-internal
  # projections, not part of the public PA schema).
  @preloads [
    account_holder: [legal_entity: [:addresses]],
    debtor_counterparty: [legal_entity: [:addresses]],
    creditor_counterparty: [legal_entity: [:addresses]],
    debtor_payment_account: [account_holder: [legal_entity: [:addresses]]],
    creditor_payment_account: [account_holder: [legal_entity: [:addresses]]]
  ]

  describe "effective_control/2" do
    test "picks the smaller cap per slot, nil meaning unconstrained" do
      a = %Control{
        daily_debit_cap: 1_000,
        daily_credit_cap: nil,
        weekly_debit_cap: 10_000,
        weekly_credit_cap: 8_000,
        monthly_debit_cap: nil,
        monthly_credit_cap: 50_000,
        yearly_debit_cap: 100_000,
        yearly_credit_cap: 150_000,
        reason: "rule_a"
      }

      b = %Control{
        daily_debit_cap: 500,
        daily_credit_cap: 2_000,
        weekly_debit_cap: 20_000,
        weekly_credit_cap: nil,
        monthly_debit_cap: 25_000,
        monthly_credit_cap: nil,
        yearly_debit_cap: nil,
        yearly_credit_cap: 100_000,
        reason: "rule_b"
      }

      merged = RuleEngine.effective_control(a, b)

      assert merged.daily_debit_cap == 500
      # one side nil → other wins
      assert merged.daily_credit_cap == 2_000
      assert merged.weekly_debit_cap == 10_000
      assert merged.weekly_credit_cap == 8_000
      assert merged.monthly_debit_cap == 25_000
      assert merged.monthly_credit_cap == 50_000
      assert merged.yearly_debit_cap == 100_000
      assert merged.yearly_credit_cap == 100_000
      assert merged.reason == "rule_a; rule_b"
    end

    test "reason handles nil + duplicate" do
      a = %Control{reason: "rule_x"}
      b = %Control{reason: nil}
      assert RuleEngine.effective_control(a, b).reason == "rule_x"
      assert RuleEngine.effective_control(b, a).reason == "rule_x"
      assert RuleEngine.effective_control(a, a).reason == "rule_x"
    end

    test "is_blocked is true if either side blocked (OR)" do
      blocking = %Control{is_blocked: true, block_reason: "ofac", reason: "ofac"}
      passing = %Control{is_blocked: false, reason: "tag"}

      assert RuleEngine.effective_control(blocking, passing).is_blocked == true
      assert RuleEngine.effective_control(passing, blocking).is_blocked == true
      assert RuleEngine.effective_control(passing, passing).is_blocked == false
      assert RuleEngine.effective_control(blocking, blocking).is_blocked == true
    end

    test "block_reason concatenates only blocking contributions" do
      blocking_a = %Control{is_blocked: true, block_reason: "ofac", reason: "ofac"}
      blocking_b = %Control{is_blocked: true, block_reason: "structuring", reason: "structuring"}
      passing = %Control{is_blocked: false, reason: "tag"}

      assert RuleEngine.effective_control(blocking_a, blocking_b).block_reason ==
               "ofac; structuring"

      # passing side doesn't bleed into block_reason even with a reason tag
      assert RuleEngine.effective_control(blocking_a, passing).block_reason == "ofac"
      assert RuleEngine.effective_control(passing, blocking_a).block_reason == "ofac"
      assert RuleEngine.effective_control(passing, passing).block_reason == nil
    end
  end

  describe "fold/1" do
    test "empty list → empty controls + nil next_screening_at" do
      assert RuleEngine.fold([]) == %{controls: %{}, next_screening_at: nil}
    end

    test "single rule passes through" do
      la = "la-1"
      c = %Control{daily_debit_cap: 100, reason: "r1"}
      result = %{controls: %{la => c}, next_screening_at: nil}
      folded = RuleEngine.fold([result])
      assert folded.controls[la] == c
      assert folded.next_screening_at == nil
    end

    test "two rules on same LA → effective_control applied" do
      la = "la-1"

      r1 = %{
        controls: %{la => %Control{daily_debit_cap: 1_000, reason: "r1"}},
        next_screening_at: nil
      }

      r2 = %{
        controls: %{la => %Control{daily_debit_cap: 500, reason: "r2"}},
        next_screening_at: nil
      }

      folded = RuleEngine.fold([r1, r2])
      assert folded.controls[la].daily_debit_cap == 500
      assert folded.controls[la].reason == "r1; r2"
    end

    test "two rules on different LAs → both preserved" do
      r1 = %{controls: %{"la-1" => %Control{daily_debit_cap: 100}}, next_screening_at: nil}
      r2 = %{controls: %{"la-2" => %Control{daily_debit_cap: 200}}, next_screening_at: nil}

      folded = RuleEngine.fold([r1, r2])
      assert Map.keys(folded.controls) |> Enum.sort() == ["la-1", "la-2"]
    end

    test "next_screening_at picks the earliest non-nil" do
      early = ~U[2026-06-01 00:00:00Z]
      late = ~U[2026-12-01 00:00:00Z]

      r1 = %{controls: %{}, next_screening_at: late}
      r2 = %{controls: %{}, next_screening_at: early}
      r3 = %{controls: %{}, next_screening_at: nil}

      assert RuleEngine.fold([r1, r2, r3]).next_screening_at == early
      assert RuleEngine.fold([r3, r1]).next_screening_at == late
      assert RuleEngine.fold([r3, r3]).next_screening_at == nil
    end

    test "blocking rule on one LA + non-blocking tag on another → both survive cleanly" do
      blocking = %Control{is_blocked: true, block_reason: "ofac", reason: "ofac"}
      tag = %Control{is_blocked: false, reason: "audit_tag"}

      r1 = %{controls: %{"la-1" => blocking}, next_screening_at: nil}
      r2 = %{controls: %{"la-2" => tag}, next_screening_at: nil}

      folded = RuleEngine.fold([r1, r2])
      assert folded.controls["la-1"].is_blocked == true
      assert folded.controls["la-1"].block_reason == "ofac"
      assert folded.controls["la-2"].is_blocked == false
      assert folded.controls["la-2"].block_reason == nil
    end
  end

  describe "build_payload/2 — payload nodes the rule engine reads" do
    test "exposes flat las[] + flat compliance_screenings[] on each PA side",
         %{tenant: tenant, session: session} do
      # Sender → debtor PA
      sender = insert(:account_holder, tenant_id: tenant.id, kyc_status: :approved)
      debtor_pa = insert(:payment_account, tenant_id: tenant.id, account_holder_id: sender.id)

      # Regime-leaf LA the rule keys output by
      debtor_leaf =
        insert(:ledger_account,
          tenant_id: tenant.id,
          account_holder_id: sender.id,
          payment_account_id: debtor_pa.id,
          la_type: :account_holder_payment_account_regime_root,
          regime: "stablecoin",
          max_daily_debit: 10_000,
          is_blocked: false
        )

      # Party-level screening on the sender (AH) — should land in debtor PA's
      # flat compliance_screenings list.
      sender_screening =
        insert(:compliance_screening,
          tenant_id: tenant.id,
          account_holder_id: sender.id,
          scope: :account_holder
        )

      # Recipient → creditor PA (kyc still in_progress)
      recipient = insert(:account_holder, tenant_id: tenant.id, kyc_status: :in_progress)

      creditor_pa =
        insert(:payment_account, tenant_id: tenant.id, account_holder_id: recipient.id)

      creditor_leaf =
        insert(:ledger_account,
          tenant_id: tenant.id,
          account_holder_id: recipient.id,
          payment_account_id: creditor_pa.id,
          la_type: :account_holder_payment_account_regime_root,
          regime: "stablecoin",
          is_blocked: true,
          block_reason: "pending onboarding screening"
        )

      # Party-level screening on the recipient AH (kyc-pending → expected to
      # show up alongside the instrument screening below).
      recipient_screening =
        insert(:compliance_screening,
          tenant_id: tenant.id,
          account_holder_id: recipient.id,
          scope: :account_holder
        )

      # Instrument-level screening directly on the creditor PA.
      creditor_pa_screening =
        insert(:compliance_screening,
          tenant_id: tenant.id,
          account_holder_id: recipient.id,
          payment_account_id: creditor_pa.id,
          scope: :payment_account,
          screened_entity_type: :payment_account
        )

      txn =
        insert(:transaction,
          tenant_id: tenant.id,
          account_holder_id: sender.id,
          transaction_type: :internal_transfer,
          debtor_payment_account_id: debtor_pa.id,
          creditor_payment_account_id: creditor_pa.id
        )

      txn = Repo.preload(txn, @preloads, skip_multi_tenancy_check: true)

      payload = RuleEngine.build_payload(session, txn)

      creditor = payload.creditor_payment_account
      debtor = payload.debtor_payment_account

      # ── las ──────────────────────────────────────────────────────────
      assert is_list(creditor["las"])
      assert is_list(debtor["las"])

      assert creditor_leaf_payload =
               Enum.find(creditor["las"], &(&1["id"] == creditor_leaf.id))

      assert creditor_leaf_payload["la_type"] == "account_holder_payment_account_regime_root"
      assert creditor_leaf_payload["regime"] == "stablecoin"
      assert creditor_leaf_payload["is_blocked"] == true
      assert creditor_leaf_payload["block_reason"] == "pending onboarding screening"

      assert debtor_leaf_payload = Enum.find(debtor["las"], &(&1["id"] == debtor_leaf.id))
      assert debtor_leaf_payload["max_daily_debit"] == 10_000
      assert debtor_leaf_payload["is_blocked"] == false

      # ── compliance_screenings (flat per side) ────────────────────────
      creditor_cs_ids = Enum.map(creditor["compliance_screenings"], & &1["id"])
      assert recipient_screening.id in creditor_cs_ids
      assert creditor_pa_screening.id in creditor_cs_ids

      debtor_cs_ids = Enum.map(debtor["compliance_screenings"], & &1["id"])
      assert sender_screening.id in debtor_cs_ids

      # Discriminator preserved on each row so the rule can filter by subject
      # type when it cares.
      assert Enum.any?(creditor["compliance_screenings"], &(&1["scope"] == "payment_account"))

      # ── nested account_holder.kyc_status still readable ──────────────
      # AH.kyc_status stays on AH; rule may read this OR look at the flat
      # screening list — its choice. Both paths must work.
      assert creditor["account_holder"]["kyc_status"] == "in_progress"
      assert debtor["account_holder"]["kyc_status"] == "approved"
    end

    test "exposes account_holder.legal_entity.addresses[] so rules can derive residency (scenario #15)",
         %{tenant: tenant, session: session} do
      # Sentinel: scenario #15 (`ah_country_kp_residence`) reads
      # `debtor_payment_account.account_holder.legal_entity.addresses[]`,
      # picks the row with `primary = true` and `address_types` containing
      # `'residential'`, and reads its `country`. The payload contract is
      # that those address rows survive Mapper.to_map untouched, with both
      # the `primary` flag and the `address_types` array intact — and that
      # the LE's `citizenship_country` stays addressable as the fallback.
      ah = insert(:account_holder, tenant_id: tenant.id, kyc_status: :approved)

      le =
        insert(:legal_entity,
          tenant_id: tenant.id,
          account_holder_id: ah.id,
          citizenship_country: "US"
        )

      # Primary residential address in KP — the scenario #15 trigger
      Repo.insert!(%LegalEntityAddress{
        tenant_id: tenant.id,
        legal_entity_id: le.id,
        address_types: ["residential"],
        primary: true,
        line1: "1 Kim Il-sung Square",
        locality: "Pyongyang",
        country: "KP"
      })

      # Non-primary mailing address in a clean country — must NOT override KP
      Repo.insert!(%LegalEntityAddress{
        tenant_id: tenant.id,
        legal_entity_id: le.id,
        address_types: ["mailing"],
        primary: false,
        line1: "1 Mailing Drop",
        locality: "Honolulu",
        country: "US"
      })

      txn = %Transaction{
        tenant_id: tenant.id,
        account_holder_id: ah.id,
        transaction_type: :credit_transfer,
        currency: "USD",
        amount: 5_000
      }

      txn = Repo.preload(txn, @preloads, skip_multi_tenancy_check: true)

      payload = RuleEngine.build_payload(session, txn)

      addresses = payload.account_holder["legal_entity"]["addresses"]
      assert is_list(addresses) and length(addresses) == 2

      residential =
        Enum.find(addresses, fn a ->
          a["primary"] == true and is_list(a["address_types"]) and
            "residential" in a["address_types"]
        end)

      assert residential != nil,
             "the primary residential address row must survive to the payload"

      assert residential["country"] == "KP",
             "country must be readable on the primary residential address row"

      # Fallback path: rules drop back to citizenship_country when no
      # primary residential address is on file. citizenship_country
      # must stay addressable on the LE map.
      assert payload.account_holder["legal_entity"]["citizenship_country"] == "US"
    end

    test "transaction node remains addressable for input fields like transaction_type",
         %{tenant: tenant, session: session} do
      ah = insert(:account_holder, tenant_id: tenant.id, kyc_status: :approved)

      txn = %Transaction{
        tenant_id: tenant.id,
        account_holder_id: ah.id,
        transaction_type: :internal_transfer,
        currency: "USD",
        amount: 5_000
      }

      txn = Repo.preload(txn, @preloads, skip_multi_tenancy_check: true)

      payload = RuleEngine.build_payload(session, txn)

      assert payload.transaction["transaction_type"] == "internal_transfer"
      assert payload.transaction["amount"] == 5_000
      assert payload.transaction["currency"] == "USD"
    end
  end
end
