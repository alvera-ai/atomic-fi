# Payments Compliance Platform

**The KYC/KYB/AML compliance SoE for payment companies — Alvera `payments` data domain**

[![License](https://img.shields.io/badge/License-Proprietary-red.svg)](LICENSE)
[![Elixir](https://img.shields.io/badge/Elixir-1.18-purple.svg)](https://elixir-lang.org)
[![Phoenix](https://img.shields.io/badge/Phoenix-1.8-orange.svg)](https://phoenixframework.org)

---

## Overview

The Payments Compliance Platform is a **System of Engagement (SoE)** in the Alvera three-tier architecture. It gives payment companies — fintechs, payment processors, e-money institutions, neobanks — a compliance backbone for KYC (Know Your Customer), KYB (Know Your Business), and AML (Anti-Money Laundering) that sits alongside their existing Stripe, JPMC, or Adyen integration without replacing it.

**Data domain:** `payments`
**MDM subject:** `AccountHolder` (ISO 20022 acmt:007, acmt:019)
**Standard:** ISO 20022 — acmt, pain, pacs, camt, auth message families
**Competes with:** Alloy, Sardine, Marqeta

### What You Can Build

| Vertical | Examples |
|----------|----------|
| **Fintechs** | Neobanks, challenger banks, digital wallets |
| **Payment Processors** | PSPs, acquirers, ISO/MSPs |
| **E-Money Institutions** | EMIs, prepaid card issuers |
| **Embedded Finance** | BaaS platforms, lending, BNPL |
| **Crypto / Digital Assets** | VASPs, exchanges requiring Travel Rule compliance |

---

## Three-Tier Position

```
SoR (Legacy)          SoE (Engagement)                SoI (Intelligence)
────────────          ────────────────                ──────────────────
Stripe                Payments Compliance        ───► Alvera Platform
JPMC          ──►     Platform (this repo)       │    ├── Data Activation Pipeline
Adyen                 ├── PostgreSQL (owner)     │    ├── MDM (AccountHolder resolution)
                      ├── Oban CDC outbound ─────┘    ├── Triplication (raw + tokenized)
                      └── PlatformSyncWorker ◄──────── ├── Agentic Workflows
                          (inbound sync)               ├── MCP Server
                                                       └── REST API + Scalar UI
```

The SoE starts alongside Stripe/JPMC/Adyen. As data accumulates and the SoE earns operational trust,
it can become the System of Record. No big-bang migration — data continuity is solved by the platform datalake.

### Platform SoI Capabilities (provided for free)

| Platform Capability | What this SoE gets |
|--------------------|-------------------|
| Data Activation | Platform syncs SoE data into the `payments` datalake |
| MDM | AccountHolder entity resolution across Stripe, JPMC, Adyen sources |
| Triplication | Regulated (raw PII) + Unregulated (tokenized) + Tokenized (SHA-256) storage |
| Compliance Screening | OFAC/SDN, PEP, AML scoring via Watchman against public feeds |
| Agentic Workflows | Stuck-KYC detection, OFAC escalation, payment recovery — triggered by datalake events |
| MCP Server | AI agents query the payments datalake without this SoE building an AI layer |

---

## Domain Model

All domain data links to **AccountHolder** as the MDM subject. All PII lives in the linked **LegalEntity** — AccountHolder itself has no PII fields.

```
AccountHolder (MDM Subject — ISO 20022 acmt:007, acmt:019)
  belongs_to :legal_entity              ← ALL PII: name, DOB, tax_id, address, email, phone
  has_many   :beneficial_owners         ← UBO chain (FinCEN CDD Rule ≥25% threshold)
  has_many   :counterparties            ← payer/payee roles (ISO 20022 <Dbtr>/<Cdtr>)
  has_one    :ledger                    ← accounting book (ISO 20022 camt:052/camt:053)
  has_many   :compliance_screenings     ← OFAC/SDN/PEP results (auth:018, camt:998)
  has_many   :kyc_requirements          ← CDD gates (FATF Recs 10/16/19/24)
  has_many   :documents                 ← identity documents (acmt:007 SupportingDocument)

BeneficialOwner                         ← ISO 20022 acmt:007 BeneficialOwnership section
  belongs_to :account_holder            ← the company being owned
  belongs_to :legal_entity              ← the person or entity who owns it
  field :ownership_pct                  ← FinCEN CDD ≥25% ownership threshold
  field :control_type                   ← :shareholder | :director | :officer | :trustee
  field :verification_status            ← :pending | :verified | :failed

Counterparty                            ← ISO 20022 pain:001 <Dbtr>/<Cdtr>
  belongs_to :account_holder
  belongs_to :legal_entity
  field :status                         ← :active | :suspended | :blocked

LegalEntity                             ← Shared identity record — all PII lives here
  field :legal_name                     ← KYC identity (tokenized in public schema)
  field :date_of_birth                  ← FATF CDD Rec 10 (tokenized)
  field :tax_id                         ← SSN / EIN / TIN (tokenized)
  field :address_*                      ← KYC address verification (tokenized)
  field :lei                            ← ISO 17442 Legal Entity Identifier (public)

Ledger                                  ← ISO 20022 camt:052/camt:053 chart-of-accounts
  belongs_to :account_holder
  field :currency                       ← ISO 4217 (one ledger per currency)
  has_many   :ledger_accounts

LedgerAccount                           ← camt:052 <Acct>, camt:053 <Acct>, camt:060
  belongs_to :ledger
  belongs_to :parent_ledger_account     ← self-referential hierarchy (MASTER→DEBIT/CREDIT→PAIR)
  field :ancestor_ids                   ← materialized path for O(1) ancestor lookup
  field :balance                        ← running balance (trigger-maintained)
  has_many   :ledger_entries
  has_many   :ledger_account_balances   ← per-day rolling period totals

LedgerEntry                             ← camt:052 <Ntry>, camt:053 <Ntry>
  belongs_to :ledger_account
  field :entry_type                     ← :debit | :credit (ISO 20022 CdtDbtInd)
  field :amount                         ← minor currency units (cents)
  field :status                         ← :pending | :posted | :reversed | :voided
  field :*_limit_at_entry               ← risk engine limit snapshot at creation time

LedgerAccountBalance                    ← per-day rolling period totals (trigger-maintained)
  belongs_to :ledger_account
  field :balance_date / :iso_week / :month / :year   ← period key
  field :daily_debit / :daily_credit                  ← day totals
  field :weekly_debit / :weekly_credit                ← week-to-date cumulative
  field :monthly_debit / :monthly_credit              ← month-to-date cumulative
  field :yearly_debit / :yearly_credit                ← year-to-date cumulative
  field :last_*_limit                   ← most recent risk engine limit (CHECK constraint source)

ComplianceScreening                     ← ISO 20022 camt:998, auth:018
  belongs_to :account_holder
  field :scope            ← :account_holder | :counterparty | :payment_account | :transaction
  field :screening_type   ← :sanctions | :pep | :aml | :adverse_media
  field :screening_status ← :pending | :pass | :potential_match | :blocked | :escalated
  has_many :sanctions_matches           ← one row per Watchman/OFAC hit
  has_many :blocklist_matches           ← one row per internal blocklist hit

SanctionsMatch                          ← per-hit Watchman result
  belongs_to :compliance_screening
  field :match_score / :source_list / :source_id
  field :false_positive_qualifier       ← :none | :manual_override | :auto_suppressed
  field :list_synced_at / :list_sources ← Watchman list version at time of this specific match
  embeds_many :addresses                ← WatchmanAddress (typed JSONB)
  embeds_one  :business_data            ← WatchmanBusiness (typed JSONB)
  embeds_one  :person_data              ← WatchmanPerson (typed JSONB)
  embeds_one  :contact_data            ← WatchmanContact (typed JSONB)
```

### LedgerAccount Hierarchy — Risk Classification Cascade

```
Ledger (AccountHolder's book)
│
└── MASTER LedgerAccount                          ← limit = f(RiskClassification.risk_level)
      │                                             :low → $50K/day  :high → $5K/day
      │
      ├── DEBIT LedgerAccount                     ← limit = min(MASTER, Counterparty.debit_daily_limit)
      │     owned by: Counterparty (outbound)
      │     └── PAIR_DEBIT LedgerAccount          ← limit = min(DEBIT, ComplianceScreening pair result)
      │           owned by: PaymentAccount
      │
      └── CREDIT LedgerAccount                    ← limit = min(MASTER, Counterparty.credit_daily_limit)
            owned by: Counterparty (inbound)
            └── PAIR_CREDIT LedgerAccount         ← limit = min(CREDIT, ComplianceScreening pair result)
                  owned by: PaymentAccount
```

**Balance trigger**: Every `ledger_entries` INSERT/UPDATE(voided) fires `propagate_ledger_entry_to_balances` — updates `ledger_accounts.balance` and upserts `ledger_account_balances` rows for the direct account AND all ancestors (via materialized `ancestor_ids`). CHECK constraints on `ledger_account_balances` enforce limits from the risk engine.

---

## Dual-Schema Architecture

Every dataset has both a **public** (tokenized for AI) and **regulated** (raw PII for humans) schema. The split is enforced consistently for LLM agentic workflow access.

### What Is Tokenized (regulated tables)

| Field | Reason |
|-------|--------|
| `legal_name`, `date_of_birth`, `tax_id` | KYC identity — FATF CDD Rec 10 |
| `nationality`, `email`, `phone` | Contact PII |
| `address_line1`, `city`, `state`, `postal_code` | KYC address verification |
| `account_number`, `routing_number`, `iban`, `card_pan` | PCI-DSS 4.0 |
| `response_content`, `extracted_fields` | KYC response data — may contain PII |
| `matched_name`, `sdn_entity_pii` | OFAC/SDN match details |
| `debtor_name`, `creditor_name`, `remittance_info` | Payment party PII (ISO 20022 RmtInf) |

### What Is NOT Tokenized (public tables — safe for AI)

| Field | Reason |
|-------|--------|
| `holder_type`, `kyc_status`, `risk_level` | Enums — not PII |
| `account_holder_number`, `ledger_account_number` | Opaque internal IDs |
| `lei` | ISO 17442 Legal Entity Identifier — public standard |
| `amount`, `currency`, `entry_type` | Transaction metadata — not PII |
| `swift_bic`, `bank_name` | Public bank identifiers |
| `screening_status`, `scope` | Workflow state — not PII |

---

## Compliance Coverage

| Regulation | Enforcement |
|-----------|-------------|
| **FATF Rec 10** — Customer Due Diligence | `ComplianceScreening` `:account_holder` scope + `KycRequirement` gate account activation |
| **FATF Rec 16** — Wire Transfer Rule | `:payment_account`-scope `KycRequirement` gates individual payment instruction |
| **FATF Rec 19** — Enhanced Due Diligence | High-risk accounts trigger `:counterparty`-scope screening and EDD requirements |
| **FATF Rec 24** — UBO Transparency | `BeneficialOwner` chain must be complete and verified; incomplete UBO blocks `AccountHolder` activation |
| **FinCEN CDD Rule** (31 CFR §1010.230) | `ownership_pct ≥ 25%` + control person verification enforced via `BeneficialOwner` |
| **OFAC Sanctions** | Watchman (Moov) screens every entity against SDN/EU/UN lists; `SanctionsMatch` per hit with false-positive dedup across re-screenings |
| **PCI-DSS 4.0** | Bank/card details tokenized via Platform triplication (`RegulatedLedgerAccount`) |
| **BSA Data Retention** | `ComplianceScreening` + `SanctionsMatch` + `BlocklistMatch` provide 5-year audit trail |

---

## ISO 20022 Message Coverage

All ISO 20022 messages for this domain are constructable from platform data:

| ISO Message | Purpose | Datasets Required |
|-------------|---------|-------------------|
| acmt:007 | Account Opening | AccountHolder + LegalEntity + BeneficialOwner + KycRequirement + Document |
| acmt:008 | Additional Info Request | KycRequirement + Document |
| acmt:019 | Account Closing | AccountHolder + LedgerAccount |
| pain:001 | Credit Transfer Initiation | Transaction + Counterparty + LegalEntity + LedgerAccount |
| pain:002 | Payment Status Report | Transaction |
| pacs:008 | FI Credit Transfer | Transaction + LedgerAccount + RegulatedLedgerAccount |
| pacs:002 | FI Payment Status | Transaction |
| pacs:004 | Payment Return | Transaction + LedgerEntry |
| camt:052 | Account Report (intraday) | LedgerAccount + LedgerEntry + AccountActivitySnapshot |
| camt:053 | Account Statement | LedgerAccount + LedgerEntry + AccountActivitySnapshot |
| camt:054 | Debit/Credit Notification | Transaction |
| camt:060 | Account Reporting Request | LedgerAccount + RegulatedLedgerAccount |
| auth:018 | Risk Classification Report | RiskClassification + ComplianceScreening |
| camt:998 | Sanctions Screening | ComplianceScreening + SanctionsMatch |

---

## Implementation Status

All contexts in the project. ISO 20022 alignment tracked in [#9](https://github.com/alvera-ai/payments-compliance-platform/issues/9).

| Context | Regulation | Schema | Docs | Tests | RLS | API | Status |
|---------|------------|--------|------|-------|-----|-----|--------|
| Tenant | — | ✅ | ✅ | ✅ | N/A | ✅ | 4/5 |
| User | — | ✅ | ✅ | ✅ | ✅ | 🔴 | 4/5 |
| Role | — | ✅ | ✅ | ✅ | ✅ | 🔴 | 4/5 |
| Customer | — | ✅ | ✅ | ✅ | ✅ | 🔴 | 4/5 |
| ApiKey | — | ✅ | ✅ | ✅ | ✅ | 🔴 | 4/5 |
| Session | — | ✅ | ✅ | ✅ | ✅ | 🔴 | 4/5 |
| LegalEntity | ISO 20022 acmt:007 · FATF Rec 10/24 | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| AccountHolder | ISO 20022 acmt:007, acmt:019 · FATF Rec 10 | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| BeneficialOwner | ISO 20022 acmt:023 · FATF Rec 24 · FinCEN CDD §1010.230 | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| BlocklistEntry ⚠️ | OFAC/SDN (pre-ISO MVP) | ✅ | ✅ | ✅ | ✅ | 🔴 | 4/5 |
| ComplianceScreening | ISO 20022 camt:998, auth:018 · FATF Rec 19 · OFAC | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| Counterparty | ISO 20022 pain:001 · FATF Rec 19 | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| Ledger | ISO 20022 camt:052, camt:053 | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| LedgerAccount | ISO 20022 camt:052, camt:053 | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| LedgerEntry | ISO 20022 camt:052, camt:053 | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| LedgerAccountBalance | ISO 20022 camt:053 | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| KycRequirement | ISO 20022 acmt:007, acmt:008 · FATF Rec 10/16/19/24 | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| Document | ISO 20022 acmt:007, acmt:008 · FATF Rec 10 | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| PaymentAccount | ISO 20022 pain:001 · FATF Rec 16 · PCI-DSS 4.0 | 🔴 | 🔴 | 🔴 | 🔴 | 🔴 | 0/5 |
| Transaction | ISO 20022 pain:001, pacs:008, pacs:002, pacs:004, camt:054 | 🔴 | 🔴 | 🔴 | 🔴 | 🔴 | 0/5 |
| AccountActivitySnapshot | ISO 20022 camt:052 · FinCEN AML | 🔴 | 🔴 | 🔴 | 🔴 | 🔴 | 0/5 |
| PartyActivitySnapshot | FATF Rec 10 · FinCEN AML | 🔴 | 🔴 | 🔴 | 🔴 | 🔴 | 0/5 |
| RiskClassification | ISO 20022 auth:018 · FATF Rec 10 | 🔴 | 🔴 | 🔴 | 🔴 | 🔴 | 0/5 |

⚠️ BlocklistEntry is a pre-ISO MVP context, superseded by ComplianceScreening + BlocklistMatch in [#9](https://github.com/alvera-ai/payments-compliance-platform/issues/9).

**Column definitions:**
- **Schema**: Ecto schema + migration, TypedEctoSchema, ISO 20022 field alignment, column comments
- **Docs**: `@moduledoc` with FATF Recommendation / ISO 20022 cross-references
- **Tests**: ExUnit DataCase tests, no mocks, real PostgreSQL
- **RLS**: Row-level security via `tenant_id` scoping in `def_with_rls_and_logging/3`
- **API**: REST endpoints with OpenAPI Request/Response schemas via ExOpenApiUtils, documented at `/api/docs`

---

## API

All endpoints under `/api`, documented at `/api/docs` (Scalar UI).

### Resources

| Resource | Endpoints |
|----------|-----------|
| Account Holders | `GET/POST /api/account-holders` · `GET/PUT/DELETE /api/account-holders/:id` |
| Beneficial Owners | `GET/POST /api/beneficial-owners` · `GET/PUT/DELETE /api/beneficial-owners/:id` |
| Counterparties | `GET/POST /api/counterparties` · `GET/PUT/DELETE /api/counterparties/:id` |
| Legal Entities | `GET/POST /api/legal-entities` · `GET/PUT/DELETE /api/legal-entities/:id` |
| Compliance Screenings | `GET /api/compliance-screenings` · `GET/PUT /api/compliance-screenings/:id` |
| Ledgers | `GET/POST /api/ledgers` · `GET/PUT/DELETE /api/ledgers/:id` |
| Ledger Accounts | `GET/POST /api/ledger-accounts` · `GET/PUT/DELETE /api/ledger-accounts/:id` |
| Ledger Entries | `GET/POST /api/ledger-entries` · `GET/PUT/DELETE /api/ledger-entries/:id` |
| Ledger Account Balances | `GET /api/ledger-account-balances` · `GET /api/ledger-account-balances/:id` |
| KYC Requirements | `GET/POST /api/kyc-requirements` · `GET/PUT/DELETE /api/kyc-requirements/:id` |
| Documents | `GET/POST /api/documents` · `GET/PUT/DELETE /api/documents/:id` |

### Compliance Screening Actions

| Endpoint | Screens |
|----------|---------|
| `POST /api/compliance-screenings/screen-account-holder` | AccountHolder against OFAC/SDN/PEP |
| `POST /api/compliance-screenings/screen-beneficial-owner` | BeneficialOwner (FinCEN CDD UBO chain) |
| `POST /api/compliance-screenings/screen-counterparty` | Counterparty pair |

### chain_screening (Automatic on Create)

Creating any AccountHolder, BeneficialOwner, or Counterparty automatically enqueues an Oban
compliance screening job (`chain_screening: true` by default):

```json
POST /api/account-holders
{
  "legal_entity_id": "...",
  "holder_type": "individual",
  "chain_screening": false
}
```

Set `"chain_screening": false` to skip — useful for bulk imports or seeding.

---

## Architecture

### Directory Structure

```
lib/
├── payment_compliance_platform/
│   ├── account_holder_context/         # AccountHolder + ISO 20022 acmt
│   ├── beneficial_owner_context/       # BeneficialOwner + FinCEN CDD
│   ├── counterparty_context/           # Counterparty + ISO 20022 pain/pacs
│   ├── legal_entity_context/           # Shared identity + PII
│   ├── compliance_screening_context/   # OFAC/SDN/PEP screening + Watchman
│   │   ├── compliance_screening.ex     # Parent screening record (auth:018, camt:998)
│   │   ├── screening_worker.ex         # Oban worker: :compliance_screening queue
│   │   ├── blocklist_match.ex          # Per-hit internal blocklist result
│   │   └── sanctions_match.ex          # Per-hit Watchman/OFAC result
│   ├── kyc_requirement_context/        # KYC gates (FATF Rec 10/16/19/24)
│   ├── document_context/               # Compliance documents (ISO 20022 acmt:007)
│   ├── decision_context/
│   │   └── screening_engine.ex         # Watchman API client
│   ├── blocklist_context/              # Internal blocklist management
│   ├── ledger_context/                 # Ledger (camt:052/camt:053 container)
│   ├── ledger_account_context/         # LedgerAccount + LedgerAccountBalance
│   ├── ledger_entry_context/           # LedgerEntry + limit snapshots
│   ├── tenant_context/                 # Multi-tenancy
│   ├── user_context/                   # User auth (bcrypt + TOTP)
│   ├── role_context/                   # RBAC
│   ├── customer_context/               # B2B customer orgs
│   ├── api_key_context/                # Machine-to-machine auth
│   └── session_context/               # Session management
│
├── payment_compliance_platform_api/
│   └── controllers/
│       ├── account_holder_controller.ex
│       ├── beneficial_owner_controller.ex
│       ├── counterparty_controller.ex
│       ├── legal_entity_controller.ex
│       ├── compliance_screening_controller.ex
│       ├── ledger_controller.ex
│       ├── ledger_account_controller.ex
│       ├── ledger_entry_controller.ex
│       ├── ledger_account_balance_controller.ex
│       ├── kyc_requirement_controller.ex
│       └── document_controller.ex
│
└── payment_compliance_platform_web/    # LiveView UI (future)

priv/repo/migrations/                   # All DB migrations in timestamp order
test/
├── payment_compliance_platform/        # Context tests (ExUnit, no mocks)
└── payment_compliance_platform_api/    # Controller tests (ConnCase)
```

### OpenAPI Schema Pattern (ExOpenApiUtils)

Schemas use `open_api_schema` annotations to auto-generate `*Request` / `*Response` structs:

- `AccountHolder` → `AccountHolderRequest` (writeOnly fields excluded) + `AccountHolderResponse` (readOnly fields only)
- `readOnly: true` on `open_api_property` → field appears only in Response struct (server-generated: `id`, timestamps)
- `writeOnly: true` → field appears only in Request struct (sensitive input: passwords, tokens)
- No flag → field appears in both Request and Response structs
- Controllers receive typed `%AccountHolderRequest{}` structs — no map conversion needed
- `ExOpenApiUtils.Changeset.cast/3` handles `Mapper.to_map` internally — pass struct directly to `changeset/2`

### Multi-Tenancy (RLS)

Every domain record is scoped to `tenant_id`. Row-level security enforced at the repo level via
`PaymentCompliancePlatform.LoggerMacro.def_with_rls_and_logging/3`.

### Background Jobs (Oban)

| Queue | Worker | Trigger |
|-------|--------|---------|
| `compliance_screening` | `ScreeningWorker` | `chain_screening: true` on create, or manual screen action |

### PostgreSQL Trigger — Balance Propagation

The `propagate_ledger_entry_to_balances` trigger fires on every `ledger_entries` INSERT or UPDATE (when `status → :voided`):

1. Computes debit/credit delta and collects `ancestor_ids` from the direct account
2. Updates `ledger_accounts.balance` for direct account + all ancestors in one `UPDATE WHERE id = ANY(v_account_ids)`
3. Upserts one `ledger_account_balances` row per account per day — stores cumulative daily/weekly/monthly/yearly debit+credit totals
4. Copies limit snapshots from the entry's `*_limit_at_entry` fields to `last_*_limit` columns on the balance row
5. CHECK constraints on `ledger_account_balances` enforce `last_*_limit IS NULL OR balance_total <= last_*_limit`

---

## CDC to Platform

This SoE syncs to the Alvera Platform SoI via Oban outbound CDC (every 5 minutes):

```
Local PostgreSQL
  └── Oban cron job (updated_at cursor)
        └── Batch changed rows since last_synced_at
              └── POST to Platform ingest endpoint
                    └── Platform: MDM Resolve → Dataset Upsert → Generate Event → Agentic Workflows
```

**Inbound sync**: `PlatformSyncWorker` polls the platform events API and writes compliance results,
MDM merges, and workflow outputs back to local DB.

---

## Getting Started

### Prerequisites

- **Erlang**: 27.3.3
- **Elixir**: 1.18.3-otp-27
- **PostgreSQL**: 17.2
- **Watchman** (optional, for sanctions screening): `docker run -p 8084:8084 moov/watchman:latest`

See `.tool-versions` for exact versions.

### Setup

```bash
# Install dependencies
mix deps.get

# Create DB, run migrations, seed
mix ecto.setup

# Start server
mix phx.server
```

**Visit:**
- **API Docs**: http://localhost:4001/api/docs
- **OpenAPI Spec**: http://localhost:4001/api/openapi

### Environment Variables

```bash
DATABASE_URL=ecto://postgres:postgres@localhost/payments_compliance_platform_dev
SECRET_KEY_BASE=generate_with_mix_phx_gen_secret
PHX_HOST=localhost
PORT=4001

# Watchman sanctions screening service
WATCHMAN_BASE_URL=http://localhost:8084

# Optional: tenant seed
TENANT_NAME=my-fintech
ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=change_me_in_production
```

---

## Development

### Running Tests

```bash
# Run all tests (494 tests, 0 failures)
mix test

# Run specific domain tests
mix test test/payment_compliance_platform/account_holder_context_test.exs
mix test test/payment_compliance_platform/ledger_account_balance_context_test.exs

# Quality checks
mix format
mix credo --strict
mix compile --warnings-as-errors
```

### Code Generators

```bash
# Generate context (Ecto schema + context + tests + RLS)
mix alvera.gen.context Payments Transaction transactions amount:integer currency:string

# Generate REST API (with OpenAPI)
mix alvera.gen.api Payments Transaction transactions
```

---

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Language | Elixir 1.18 / OTP 27 |
| Web framework | Phoenix 1.8 + Phoenix LiveView |
| Database | PostgreSQL 17.2 with RLS + triggers |
| API documentation | OpenApiSpex + Scalar UI |
| Schema generation | ExOpenApiUtils (Request/Response auto-split) |
| Background jobs | Oban — `compliance_screening` queue |
| Compliance screening | Moov Watchman (OFAC/SDN/EU/UN lists) |
| Auth | bcrypt + TOTP 2FA + API keys |
| Pagination/filtering | Flop |
| Testing | ExUnit (DataCase + ConnCase, no mocks) |
| CI/CD | GitHub Actions (test + quality + Docker) |

---

## Contributing

Maintained by Alvera AI. Internal use only.

Before committing:
1. `mix format && mix credo --strict && mix test`
2. Follow [CLAUDE.md](CLAUDE.md) — GPG-sign all commits (`git commit -S`)
3. Update this README's capability matrix when completing dataset work
4. Conventional commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`

---

## License

Copyright © 2026 Alvera AI. All rights reserved.
