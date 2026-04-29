# Capability Matrix

Implementation status for every context in the Payments Compliance Platform SoE.

**Last Updated:** February 2026

---

## Column Definitions

| Column | Definition |
|--------|-----------|
| **Schema** | Ecto schema and migration — TypedEctoSchema, RLS `tenant_id`, ISO 20022 / FATF field alignment, table/column comments |
| **Docs** | `@moduledoc` + `@typedoc` with field descriptions, FATF/ISO cross-references, iex examples |
| **Tests** | ExUnit tests via DataCase (no mocks, real DB sandbox) — create/read/update/delete + error cases |
| **RLS** | Row-level security via `tenant_id` scoping using `def_with_rls_and_logging` |
| **API** | OpenAPI-documented REST endpoints — `*Request`/`*Response` schemas, Scalar UI visible |

**Legend:**
- ✅ Fully implemented
- ⚠️ Partial — implemented but needs work
- 🔴 Not started
- N/A — Not applicable for this context

---

## Platform Infrastructure Contexts

These contexts provide the foundational multi-tenancy, auth, and session plumbing used by all domain contexts.

| Context | Schema | Docs | Tests | RLS | API | Score | Notes |
|---------|--------|------|-------|-----|-----|-------|-------|
| TenantContext | ✅ | ✅ | ✅ | N/A | ✅ | 4/5 | Top-level entity — RLS not applicable (is the RLS root) |
| UserContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 | bcrypt + TOTP 2FA |
| RoleContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 | RBAC scopes |
| CustomerContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 | Optional multi-customer-per-tenant segmentation |
| ApiKeyContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 | Machine-to-machine auth |
| SessionContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 | Bearer session lifecycle (login / verify / revoke) |

**Infrastructure Progress:**
- Schema: 6/6 (100%)
- Docs: 6/6 (100%)
- Tests: 6/6 (100%)
- RLS: 5/5 (100%) — N/A for TenantContext
- API: 6/6 (100%)

---

## Domain Contexts (payments data domain — ISO 20022 / FATF)

These contexts implement the KYC/KYB/AML compliance data model for the `payments` datalake.
All are aligned to ISO 20022 message families and FATF CDD Rule recommendations.

| Context | Schema | Docs | Tests | RLS | API | Score | ISO 20022 | FATF |
|---------|--------|------|-------|-----|-----|-------|-----------|------|
| LegalEntityContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 | Shared identity record | Rec 10 — identity fields |
| AccountHolderContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 | acmt:007, acmt:019 | MDM subject — KYC state |
| BeneficialOwnerContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 | acmt:007 BeneficialOwnership | Rec 24, FinCEN CDD ≥25% |
| CounterpartyContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 | pain:001 `<Dbtr>`/`<Cdtr>` | Rec 19 — EDD |
| ComplianceScreeningContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 | camt:998, auth:018 | OFAC/SDN/PEP screening |
| BlocklistContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 | — | Tenant-managed internal blocklist (ETS-cached) |
| PartyActivitySnapshotContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 | — | Party-level AML period snapshot — Rec 10 · FinCEN AML |
| RiskClassificationContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 | auth:018 | Formal risk record — drives LedgerAccount limit cascade |

**Domain Progress:**
- Schema: 8/8 (100%)
- Docs: 8/8 (100%)
- Tests: 8/8 (100%)
- RLS: 8/8 (100%)
- API: 8/8 (100%)

---

## Overall Progress Summary

| Capability | Infrastructure | Domain | Total |
|-----------|---------------|--------|-------|
| Schema | 6/6 ✅ | 8/8 ✅ | **14/14 (100%)** |
| Docs | 6/6 ✅ | 8/8 ✅ | **14/14 (100%)** |
| Tests | 6/6 ✅ | 8/8 ✅ | **14/14 (100%)** |
| RLS | 5/6 ✅ | 8/8 ✅ | **13/14 (93%)** — N/A for Tenant |
| API | 6/6 ✅ | 8/8 ✅ | **14/14 (100%)** |

---

## Context Detail

### LegalEntityContext

**Purpose:** Shared identity record — all PII lives here. Both AccountHolder and BeneficialOwner
reference LegalEntity. Analogous to `Patient.name` in FHIR — the identity layer is separate from
the operational state layer.

**Key fields:** `legal_name`, `date_of_birth`, `tax_id` (SSN/EIN/TIN), `nationality`,
`email`, `phone`, `address_*`, `lei` (ISO 17442), `legal_entity_type` (`:individual | :business`)

**ISO 20022:** Provides the identity fields for acmt:007 Account Opening, pain:001 party names

**Regulatory:** FATF Rec 10 CDD — collect and verify identity before establishing relationship

---

### AccountHolderContext

**Purpose:** The MDM subject for the `payments` data domain. Holds KYC lifecycle state
(`kyc_status`), risk classification (`risk_level`), and holder type. Zero PII — all identity
fields live in the linked LegalEntity.

**Key fields:** `holder_type` (`:individual | :business | :trust | :nonprofit`),
`status` (`:pending | :active | :suspended | :closed | :flagged`),
`kyc_status` (`:not_started | :in_progress | :approved | :rejected | :expired`),
`risk_level` (`:low | :medium | :high | :very_high`),
`enabled_currencies` (ISO 4217 codes),
`chain_screening` (virtual — enqueues Oban job on create)

**ISO 20022:** acmt:007 (Account Opening), acmt:019 (Account Closing)

**SAS AML equivalent:** `FSC_PARTY_DIM`

**chain_screening behavior:**
- `true` (default) → enqueues `ScreeningWorker` on Oban `:compliance_screening` queue after insert
- `false` → skips screening (bulk import, seeds)

---

### BeneficialOwnerContext

**Purpose:** Ultimate Beneficial Owner (UBO) chain for corporate AccountHolders. Each row links
a company AccountHolder to the person or entity that owns ≥25% of it, per FinCEN CDD Rule.
Also captures control persons (directors, officers) regardless of ownership percentage per FATF Rec 24.

**Key fields:** `ownership_pct`, `control_type` (`:shareholder | :director | :officer | :trustee`),
`verification_status` (`:pending | :verified | :failed`),
`chain_screening` (virtual — enqueues Oban job on create)

**ISO 20022:** acmt:007 BeneficialOwnership section, pain:001 UltimateDebtor

**Regulatory:** FinCEN CDD Rule (31 CFR §1010.230), FATF Rec 24

**SAS AML equivalent:** `FSC_PARTY_ASSOC`

---

### CounterpartyContext

**Purpose:** External payer/payee relationship for an AccountHolder. A single Counterparty
holds both the outbound (debtor) and inbound (creditor) identity. All PII for the external party
lives in the linked LegalEntity. Counterparty activation is gated by ComplianceScreening.

**Key fields:** `status` (`:active | :suspended | :blocked`),
`chain_screening` (virtual — enqueues Oban job on create)

**ISO 20022:** pain:001 `<Dbtr>`/`<Cdtr>`, pacs:008 `<DbtrAgt>`/`<CdtrAgt>`

**Regulatory:** FATF Rec 19 — EDD for high-risk counterparty relationships

**SAS AML equivalent:** `FSC_PARTY_ACCOUNT_BRIDGE`

---

### ComplianceScreeningContext

**Purpose:** OFAC/SDN, PEP, and internal blocklist screening results. Three scopes:
`:account_holder` (entity-level), `:beneficial_owner` (UBO), `:counterparty` (relationship-level).
Supports manual false-positive review workflow (`reviewed_by`, `reviewed_at`, `false_positive`).

**Key fields:** `scope` (`:account_holder | :beneficial_owner | :counterparty`),
`result` (`:clear | :potential_match | :confirmed_match | :error`),
`false_positive`, `reviewed_by_user_id`, `reviewed_at`

**ISO 20022:** camt:998 (proprietary sanctions), auth:018 (RiskClassificationReport)

**Regulatory:** OFAC Executive Orders, BSA SAR (5-year retention)

**SAS AML equivalent:** `FSC_CLASSIFIER_FACT`

**Oban worker:** `ScreeningWorker` on `:compliance_screening` queue. Triggered by
`chain_screening: true` on AccountHolder, BeneficialOwner, or Counterparty create.
Also callable directly via `POST /api/compliance-screenings/screen-*` endpoints.

**Screen actions (API):**

| Endpoint | Context function |
|----------|-----------------|
| `POST /screen-account-holder` | `ComplianceScreeningContext.screen_account_holder/2` |
| `POST /screen-beneficial-owner` | `ComplianceScreeningContext.screen_beneficial_owner/2` |
| `POST /screen-counterparty` | `ComplianceScreeningContext.screen_counterparty/2` |

---

### BlocklistContext

**Purpose:** Tenant-managed internal blocklist of known bad actors by `first_name`,
`last_name`, or `company_name` (exact or regex). Complements OFAC/SDN sanctions
screening — the screening engine reads these at runtime via ETS cache (refreshed
automatically on create/update/delete). Distinct from `BlocklistMatch`, which is
the per-hit audit record produced by the screening engine.

---

### PartyActivitySnapshotContext

**Purpose:** Period-level AML monitoring summary for an AccountHolder — KYC /
risk-level transitions, screening volume and hit rate, aggregate transaction
shape, and SAR candidacy across a reporting window. Distinct from
AccountActivitySnapshot (which is ledger-level camt:052/camt:053).

**Regulatory:** FATF Rec 10 (ongoing CDD) · FinCEN 31 CFR §1020.320 (SAR filing)

**Key fields:** `period_type` (daily/weekly/monthly/quarterly),
`kyc_status_at_{start,end}`, `risk_level_at_{start,end}`, `total_screenings`,
`screening_hits`, `transaction_count`, `total_{debit,credit}_amount`,
`high_risk_transaction_count`, `sar_indicator`, `notes`

---

### RiskClassificationContext

**Purpose:** Formal risk classification record per AccountHolder. The active
classification drives the LedgerAccount limit cascade — MASTER LedgerAccount
velocity limits are `f(RiskClassification.risk_level)`. Exactly one
`is_active = true` record exists per `(holder, tenant)` at a time; creating or
activating a new one deactivates the prior active record atomically.

**Regulatory:** ISO 20022 auth:018 (CustomerRiskAssessment) · FATF Rec 10 (risk-based CDD)

**Key fields:** `risk_level` (low/medium/high/very_high), `classification_reason`,
`effective_from`, `effective_until`, `is_active`, `classified_by_user_id`
(nil = auto-classified), `compliance_screening_id`

---

## ISO 20022 Message Coverage

All ISO 20022 messages for the `payments` domain are constructable from this SoE's data:

| ISO Message | Datasets Required |
|-------------|------------------|
| acmt:007 Account Opening | AccountHolder + LegalEntity + BeneficialOwner |
| acmt:019 Account Closing | AccountHolder |
| pain:001 Credit Transfer Initiation | Counterparty + LegalEntity |
| camt:998 Sanctions Screening | ComplianceScreening |
| auth:018 Risk Classification Report | ComplianceScreening |

---

## Next Work

### Near-term

| Item | Context | Effort |
|------|---------|--------|
| OSS single-tenant fork | Platform-wide | Medium — strip tenant/customer, simplify auth |
| Rename `alvera.gen.*` mix tasks | Generators | Small — cosmetic, repo-neutral naming |
| E2E controller tests | All domain contexts | Medium |

---

## Testing Patterns

```elixir
# Context tests use DataCase + real DB (no mocks)
defmodule AtomicFi.AccountHolderContextTest do
  use AtomicFi.DataCase
  import AtomicFi.Factory

  alias AtomicFi.AccountHolderContext
  alias AtomicFi.OpenApiSchema.AccountHolderRequest

  test "create_account_holder/2 with valid data creates an account_holder", %{session: session} do
    legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

    # Full struct — all fields set explicitly (full replacement convention)
    request = %AccountHolderRequest{
      legal_entity_id: legal_entity.id,
      holder_type: :individual,
      status: :pending,
      kyc_status: :not_started,
      risk_level: :low,
      enabled_currencies: ["USD"],
      tenant_id: session.tenant_id,
      chain_screening: false      # skip Oban in unit tests
    }

    assert {:ok, %AccountHolder{} = account_holder} =
             AccountHolderContext.create_account_holder(session, request)

    assert account_holder.holder_type == :individual
    assert account_holder.tenant_id == session.tenant_id
  end
end
```

```bash
# Run all context tests
mix test test/atomic_fi/

# Run all controller tests
mix test test/atomic_fi_api/

# Full suite (292 tests, 0 failures)
mix test
```
