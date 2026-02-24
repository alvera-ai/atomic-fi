# Payments Compliance Platform

**The KYC/KYB/AML compliance sidecar for payment companies — Alvera `payments` data domain SoE**

[![License](https://img.shields.io/badge/License-Proprietary-red.svg)](LICENSE)
[![Elixir](https://img.shields.io/badge/Elixir-1.18-purple.svg)](https://elixir-lang.org)
[![Phoenix](https://img.shields.io/badge/Phoenix-1.8-orange.svg)](https://phoenixframework.org)

---

## What This Is

The Payments Compliance Platform is a **System of Engagement (SoE)** in the Alvera three-tier architecture. It gives payment companies — fintechs, payment processors, e-money institutions, neobanks — a compliance backbone for KYC (Know Your Customer), KYB (Know Your Business), and AML (Anti-Money Laundering) that sits alongside their existing Stripe, JPMC, or Adyen integration without replacing it.

**Data domain:** `payments`
**MDM subject:** `AccountHolder` (ISO 20022)
**Standard:** ISO 20022 — acmt, pain, pacs, camt, auth message families
**Competes with:** Alloy, Sardine, Marqeta

---

## Three-Tier Position

```
SoR (Legacy)          SoE (Engagement)                SoI (Intelligence)
────────────          ────────────────                ──────────────────
Stripe                Payments Compliance        ───► Alvera Platform
JPMC          ──►     Platform (this repo)       │    |── Data Activation Pipeline
Adyen                 └── owns PostgreSQL        │    |── MDM (AccountHolder)
                      └── Oban CDC outbound ─────┘    |── Triplication
                      └── PlatformSyncWorker ◄──────── |── Agentic Workflows
                          (inbound sync)               |── MCP Server
                                                       |── Compliance Screening
                                                       |── REST API
```

The SoE starts alongside Stripe/JPMC/Adyen. As data accumulates and the SoE earns operational trust,
it can become the System of Record. No big-bang migration — data continuity is solved by the platform datalake.

### What the Platform SoI provides (for free)

| Platform Capability | What this SoE gets |
|--------------------|--------------------|
| Data Activation | Platform syncs SoE data into the `payments` datalake |
| MDM | AccountHolder entity resolution across Stripe, JPMC, Adyen sources |
| Triplication | Regulated (raw PII) + Unregulated (tokenized) + Tokenized (SHA-256) storage |
| Compliance Screening | OFAC/SDN, PEP, AML scoring against public data feeds |
| Agentic Workflows | Stuck-KYC detection, OFAC escalation, payment recovery — triggered by datalake events |
| MCP Server | AI agents query the payments datalake without this SoE building an AI layer |

---

## Domain Model

All domain data links to **AccountHolder** as the MDM subject. All PII lives in the linked **LegalEntity** — AccountHolder itself has no PII fields.

```
AccountHolder (MDM Subject — ISO 20022 acmt:007, acmt:019)
  belongs_to :legal_entity              ← ALL PII: name, DOB, tax_id, address
  has_many   :beneficial_owners         ← UBO chain (FinCEN CDD Rule ≥25% threshold)
  has_many   :counterparties            ← external payer/payee roles (ISO 20022 <Dbtr>/<Cdtr>)
  has_many   :compliance_screenings     ← OFAC/SDN/PEP results

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
  field :legal_name                     ← KYC identity
  field :date_of_birth                  ← FATF CDD Rec 10
  field :tax_id                         ← SSN / EIN / TIN
  field :address_*                      ← KYC address verification
  field :lei                            ← ISO 17442 Legal Entity Identifier

ComplianceScreening                     ← ISO 20022 camt:998, auth:018
  belongs_to :account_holder
  field :scope                          ← :account_holder | :beneficial_owner | :counterparty
  field :result                         ← :clear | :potential_match | :confirmed_match | :error
  field :reviewed_by / :false_positive  ← Manual review workflow
```

---

## Compliance Coverage

| Regulation | Enforcement in this app |
|-----------|------------------------|
| FATF Rec 10 — Customer Due Diligence | ComplianceScreening `:account_holder` scope gates account activation |
| FATF Rec 16 — Wire Transfer Rule | Counterparty compliance gates payment routing |
| FATF Rec 19 — Enhanced Due Diligence | High-risk accounts trigger `:counterparty` screening |
| FATF Rec 24 — UBO Transparency | BeneficialOwner chain must be complete and verified |
| FinCEN CDD Rule (31 CFR §1010.230) | `ownership_pct ≥ 25%` + control person verification enforced |
| OFAC Sanctions Screening | Watchman service screens against SDN/PEP lists on every entity creation |
| PCI-DSS 4.0 | Bank/card details tokenized (Platform triplication handles regulated storage) |
| BSA Data Retention | ComplianceScreening + audit trail provides 5-year retention |

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
| Compliance Screenings | `GET /api/compliance-screenings` · `GET/PUT/DELETE /api/compliance-screenings/:id` |

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
│   ├── compliance_screening_context/   # OFAC/SDN/PEP screening + Oban worker
│   │   ├── compliance_screening.ex
│   │   ├── screening_request.ex
│   │   ├── screening_worker.ex         # Oban worker: :compliance_screening queue
│   │   ├── blocklist_match.ex
│   │   └── sanctions_match.ex
│   ├── decision_context/
│   │   └── screening_engine.ex         # Watchman API client
│   ├── blocklist_context/              # Internal blocklist management
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
│       └── compliance_screening_controller.ex
│
└── payment_compliance_platform_web/    # LiveView UI (future)

priv/repo/migrations/                   # All DB migrations in timestamp order
test/
├── payment_compliance_platform/        # Context tests (ExUnit, no mocks)
└── payment_compliance_platform_api/    # Controller tests (ConnCase)
```

### Multi-Tenancy (RLS)

Every domain record is scoped to `tenant_id`. Row-level security enforced at the repo level via
`PaymentCompliancePlatform.LoggerMacro.def_with_rls_and_logging/3`.

### OpenAPI Schema Pattern (ExOpenApiUtils)

Schemas use `open_api_schema` annotations to auto-generate `*Request` / `*Response` structs:

- `AccountHolder` → `AccountHolderRequest` (writeOnly fields excluded) + `AccountHolderResponse` (readOnly fields only)
- Controllers receive typed `%AccountHolderRequest{}` structs — no map conversion needed
- Context functions pattern-match on typed structs: `%AccountHolderRequest{} = request`
- `ExOpenApiUtils.Changeset.cast/3` handles `Mapper.to_map` internally — pass struct directly to `changeset/2`

### Background Jobs (Oban)

| Queue | Worker | Trigger |
|-------|--------|---------|
| `compliance_screening` | `ScreeningWorker` | `chain_screening: true` on create, or manual screen action |

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
# Run all tests (292 tests, 0 failures)
mix test

# Run specific domain tests
mix test test/payment_compliance_platform/account_holder_context_test.exs
mix test test/payment_compliance_platform/compliance_screening_context_test.exs

# Quality checks
mix format
mix credo --strict
```

### Code Generators

```bash
# Generate context (Ecto schema + context + tests + RLS)
mix alvera.gen.context Payments Transaction transactions amount:integer currency:string

# Generate REST API (with OpenAPI)
mix alvera.gen.api Payments Transaction transactions
```

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

## Implementation Status

See **[Capability Matrix](guides/capability-matrix.md)** for detailed per-context status.

| Context | Schema | Docs | Tests | RLS | API | Status |
|---------|--------|------|-------|-----|-----|--------|
| TenantContext | ✅ | ✅ | ✅ | N/A | ✅ | 4/5 |
| UserContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| RoleContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| CustomerContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| ApiKeyContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| SessionContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| LegalEntityContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| AccountHolderContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| BeneficialOwnerContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| CounterpartyContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| ComplianceScreeningContext | ✅ | ✅ | ✅ | ✅ | ✅ | 5/5 |
| BlocklistContext | ✅ | ✅ | ✅ | ✅ | 🔴 | 4/5 |

**Progress Summary:**
- **Schema**: 12/12 (100%) — TypedEctoSchema with RLS, ISO 20022 field alignment
- **Docs**: 12/12 (100%) — `@moduledoc`, `@typedoc` with FATF/ISO cross-references
- **Tests**: 12/12 (100%) — ExUnit, no mocks, real DB via DataCase sandbox
- **RLS**: 11/11 (100%) — `tenant_id` scoping (N/A for TenantContext)
- **API**: 11/12 (92%) — OpenAPI-documented REST endpoints (BlocklistContext pending)

---

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Language | Elixir 1.18 / OTP 27 |
| Web framework | Phoenix 1.8 + Phoenix LiveView |
| Database | PostgreSQL 17.2 with RLS |
| API documentation | OpenApiSpex + Scalar UI |
| Schema generation | ExOpenApiUtils (Request/Response auto-split) |
| Background jobs | Oban (free) — `compliance_screening` queue |
| Compliance screening | Moov Watchman (OFAC/SDN/PEP) |
| Auth | bcrypt + TOTP 2FA + API keys |
| Pagination/filtering | Flop |
| Testing | ExUnit (DataCase + ConnCase, no mocks) |
| CI/CD | GitHub Actions (test + quality + Docker) |

---

## Version Requirements

- **Erlang**: 27.3.3
- **Elixir**: 1.18.3-otp-27
- **PostgreSQL**: 17.2

See `.tool-versions` for exact versions.

---

## Contributing

Maintained by Alvera AI. Internal use only.

Before committing:
1. `mix format && mix credo --strict && mix test`
2. Follow [CLAUDE.md](CLAUDE.md) — GPG-sign all commits (`git commit -S`)
3. Update [Capability Matrix](guides/capability-matrix.md) when completing context work
4. Conventional commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`

---

## License

Copyright © 2026 Alvera AI. All rights reserved.
