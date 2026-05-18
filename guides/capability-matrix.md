# Capability Matrix

Implementation status for every context and domain module in `atomic-fi`.

**Last Updated:** May 2026

---

## Column Definitions

| Column | Definition |
|--------|-----------|
| **Schema** | Ecto schema + migration — TypedEctoSchema, RLS `tenant_id`, ISO 20022 / FATF field alignment, table/column comments |
| **Docs** | `@moduledoc` + `@typedoc` with field descriptions, regulatory cross-references, iex examples |
| **Tests** | ExUnit context tests via `DataCase` (real DB, no mocks) — CRUD + error + RLS isolation |
| **RLS** | Row-level security via `tenant_id` scoping (`def_with_rls_and_logging`) |
| **API** | OpenAPI-documented REST endpoints — auto-generated `*Request`/`*Response` schemas, ConnCase tests |
| **Vitest** | TypeScript SDK end-to-end coverage in `integration-tests/tests/` |

**Legend:** ✅ done · ⚠️ partial · 🔴 not started · N/A not applicable

---

## Identity & Auth

Multi-tenancy partition, authentication, RBAC, session lifecycle.

| Context | Schema | Docs | Tests | RLS | API | Vitest | Notes |
|---|---|---|---|---|---|---|---|
| `TenantContext` | ✅ | ✅ | ✅ | N/A | ✅ | ✅ | RLS root — `tenant_id` mirrors `id` via `GENERATED ALWAYS AS` |
| `UserContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | bcrypt + TOTP 2FA |
| `RoleContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | RBAC scopes; `UserRoleMapping` join |
| `ApiKeyContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Bearer M2M auth |
| `SessionContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Bearer login / verify / revoke |

---

## Compliance Subjects (Parties)

The internal/external parties involved in any payment, plus their PII container.

| Context | Schema | Docs | Tests | RLS | API | Vitest | Notes |
|---|---|---|---|---|---|---|---|
| `AccountHolderContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | MDM subject. ISO 20022 acmt:007 / acmt:019. `chain_screening` enqueues Oban. |
| `CounterpartyContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | External party. ISO 20022 pain:001 `<Dbtr>`/`<Cdtr>`. Get-or-create on `external_id`. PA/CP lifecycle hook fans out LAs. |
| `LegalEntityContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | PII container. `cast_assoc` Addresses / Identifications / PhoneNumbers. FATF Rec 10. |
| `LegalEntityChangeEventContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Audit trail of LE mutations — gates re-screening. |
| `BeneficialOwnerContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | FinCEN CDD chain. Recursive — BO has its own LE. |

---

## Compliance Operations

Screening lifecycle, hits, KYC obligations, evidence, risk tiering.

| Context | Schema | Docs | Tests | RLS | API | Vitest | Notes |
|---|---|---|---|---|---|---|---|
| `ComplianceScreeningContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Per-subject screening lifecycle. Owns `SanctionsMatch` + `BlocklistMatch`. |
| `BlocklistContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Tenant-managed deny list (`BlocklistEntry`). ETS-warm cache per tenant. |
| `KycRequirementContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Open compliance obligations on AH / CP. |
| `DocumentContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Evidence pointers (S3 key, content hash, MIME, provenance). |
| `RiskClassificationContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Tier + score; one active per AH/CP. Consumed by RuleEngine. |

---

## Payment Ledger

Double-entry bookkeeping with DB-enforced tree shape + velocity limits.

| Context | Schema | Docs | Tests | RLS | API | Vitest | Notes |
|---|---|---|---|---|---|---|---|
| `PaymentAccountContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ISO 20022 instrument. Lifecycle hook materialises direct-line LAs on every write. Requires `currency`. |
| `LedgerContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | One per `(AH, currency)`. |
| `LedgerAccountContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Six `la_type` shapes. PG triggers resolve `ancestor_ids`, back-fill `descendant_ids`, refresh `LinkedLedgerAccount` edges. |
| `LedgerAccountBalanceContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Per-period rows; trigger-maintained from `LedgerEntry`. `last_*_limit` columns enforce velocity CHECKs. |
| `LedgerEntryContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ISO 20022 `CdtDbtInd`. Carries `limits_at_entry` (`velocity_limit[]`). Voided entries record `rejected_*`. |
| `TransactionContext` | ✅ | ⚠️ | ⚠️ | ✅ | ✅ | ⚠️ | Debtor + creditor PA pair. Rule-engine + leaf-LA selection still under rewrite (B.4). |

---

## Snapshots & Activity

Periodic projections consumed by the rule engine and audit views.

| Context | Schema | Docs | Tests | RLS | API | Vitest | Notes |
|---|---|---|---|---|---|---|---|
| `AccountActivitySnapshotContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Per-`PaymentAccount` activity rollup. ISO 20022 camt:052 / camt:053 shape. |
| `PartyActivitySnapshotContext` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Per-AH / per-CP rollup — KYC transitions, screening volume, SAR candidacy. FATF Rec 10 ongoing CDD. |

---

## Domain Modules (no schema)

Stateless decision modules wrapped over external transports. No schema / RLS
(they don't own data) but they have their own Mox seam and test surface.

| Module | Docs | Tests | API | Mock seam | Notes |
|---|---|---|---|---|---|
| `DecisionContext.ScreeningEngine` (+ `Behaviour`) | ✅ | ✅ | N/A | `ScreeningEngineMock` | Takes preloaded AH/CP/LE/BO structs, returns matches. Transport: `Watchman.Client`. |
| `DecisionContext.BlocklistCache` | ✅ | ✅ | N/A | — | ETS-warm tenant blocklist. Refreshed on `Blocklist` write or Quantum tick. |
| `DecisionContext.BlocklistValidator` | ✅ | ✅ | N/A | — | Name / DOB / country / tax-ID matching rules. |
| `RuleEngine` (+ `Behaviour`) | ✅ | ✅ | N/A | `RuleEngineMock` | Returns `%{la_id => [VelocityLimit]}` per transaction. |
| `RuleEngine.ZenRule` | ✅ | ✅ | N/A | — | Production impl over `ZenRule.Client`. Decodes via `VelocityLimit` embedded schema. |

---

## Test Layer Coverage

The four-layer test order is `context → controller → vitest → bruno`
([details in `architecture.md`](./architecture.md#testing-layers)).

| Layer | Status | Notes |
|---|---|---|
| 1. ExUnit context (`DataCase`) | ✅ 988 / 0 | Every context has a `_context_test.exs`. |
| 2. ExUnit controller (`ConnCase`) | ✅ | Every controller has a `_controller_test.exs` with schema asserts. |
| 3. vitest (`integration-tests/tests/`) | ⚠️ | Specs exist for every resource; some assertions stale post-reshape (Step C in p0 plan). |
| 4. Bruno (`bruno/atomic-fi-scenarios/`) | ⚠️ | 32 `.bru` files in `smoke-tests/`; some asserts stale (Step D in p0 plan). |

---

## ISO 20022 Message Coverage

All listed messages are constructable from the SoE's data — no external joins
required.

| Message | Domain | Composed From |
|---|---|---|
| acmt:007 Account Opening | onboarding | `AccountHolder` + `LegalEntity` + `BeneficialOwner` |
| acmt:019 Account Closing | offboarding | `AccountHolder` |
| pain:001 Credit Transfer Initiation | payment | `Counterparty` + `LegalEntity` + `Transaction` + `PaymentAccount` |
| pacs:008 FI-to-FI Customer Credit | payment | `Transaction` + `PaymentAccount` (debtor + creditor agents) |
| camt:052 Bank-to-Customer Account Report | reporting | `LedgerAccount` + `LedgerAccountBalance` + `LedgerEntry` |
| camt:053 Bank-to-Customer Statement | reporting | `LedgerAccount` + `LedgerAccountBalance` + `LedgerEntry` |
| camt:998 Sanctions Screening | compliance | `ComplianceScreening` + `SanctionsMatch` |
| auth:018 Customer Risk Assessment | compliance | `RiskClassification` + `ComplianceScreening` |

---

## Regulatory Coverage

| Framework | Where it lands |
|---|---|
| **FATF Rec 10** (CDD — identify & verify) | `LegalEntity` fields, `KycRequirement`, `RiskClassification`, `PartyActivitySnapshot` (ongoing CDD) |
| **FATF Rec 16** (wire transfers — originator/beneficiary info) | `Transaction` debtor/creditor pair + `PaymentAccount` + `LegalEntity` |
| **FATF Rec 19** (EDD — high-risk counterparties) | `Counterparty.status` + `RiskClassification` gating |
| **FATF Rec 24** (beneficial ownership) | `BeneficialOwner` chain |
| **FinCEN CDD Rule** (31 CFR §1010.230, ≥25% ownership) | `BeneficialOwner.ownership_pct` + `control_type` |
| **FinCEN SAR** (31 CFR §1020.320) | `PartyActivitySnapshot.sar_indicator` |
| **OFAC sanctions** | `ComplianceScreening` → `SanctionsMatch` (via Watchman) |
| **PCI-DSS 4.0** | `PaymentAccount.card_pan` (tokenised input) |

---

## Next Work

| Item | Effort | Tracking |
|---|---|---|
| B.4 — Transaction flow rewrite (`{applicable, not_applicable}` rule-engine shape; retire `:no_limits` default) | Medium | `worklogs/p0-baseline-handover.md` |
| Step A — Coverage lift core modules to ≥95%, overall ≥93% | Medium | `coveralls.json` threshold bump |
| Step C — vitest specs refreshed against post-reshape shapes | Small | per resource |
| Step D — Bruno scenarios refreshed | Small | per scenario |
| `docs/architecture.md` (Docusaurus mirror, C4 levels) | Small | Step E |
