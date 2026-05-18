defmodule AtomicFi.RuleEngine.PayloadTest do
  use AtomicFi.DataCase, async: true

  alias AtomicFi.RuleEngine.Payload
  alias AtomicFi.TransactionContext.Transaction

  alias AtomicFi.LegalEntityContext.LegalEntityAddress
  alias AtomicFi.Repo

  # Mirrors TransactionContext.@rule_engine_preloads — the production txn flow
  # preloads this exact shape before handing the entity tree to the rule engine.
  # `las` and `compliance_screenings` are NOT preloaded — Payload queries them
  # fresh from each PA at build time (rule-engine-internal projections, not
  # part of the public PA schema).
  @preloads [
    account_holder: [legal_entity: [:addresses]],
    debtor_counterparty: [legal_entity: [:addresses]],
    creditor_counterparty: [legal_entity: [:addresses]],
    debtor_payment_account: [account_holder: [legal_entity: [:addresses]]],
    creditor_payment_account: [account_holder: [legal_entity: [:addresses]]]
  ]

  describe "from_transaction/1 — payload nodes the rule engine reads" do
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

      payload = Payload.from_transaction(session, txn)

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

    test "projects country_of_residence on account_holder.legal_entity from primary residential address (scenario #15)",
         %{tenant: tenant, session: session} do
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

      payload = Payload.from_transaction(session, txn)

      assert payload.account_holder["legal_entity"]["country_of_residence"] == "KP",
             "country_of_residence must derive from the primary residential address"

      # Existing citizenship_country stays addressable (different concept)
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

      payload = Payload.from_transaction(session, txn)

      assert payload.transaction["transaction_type"] == "internal_transfer"
      assert payload.transaction["amount"] == 5_000
      assert payload.transaction["currency"] == "USD"
    end
  end
end
