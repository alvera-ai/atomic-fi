# AtomicFi

**Payments and compliance, welded into one atomic database transaction.**

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Elixir](https://img.shields.io/badge/Elixir-1.18-purple.svg)](https://elixir-lang.org)
[![Phoenix](https://img.shields.io/badge/Phoenix-1.8-orange.svg)](https://phoenixframework.org)

---

## Why AtomicFi

Money is starting to move at the pace of AI. Agents open accounts, classify counterparties, and initiate payments in seconds; humans are no longer the rate-limiting step in the loop. The constraint shifts from *speed* to *correctness under speed* — money has to move that fast, **without mistakes**.

The mistakes that matter are not arithmetic. They are state mistakes: paying a counterparty whose sanctions screening was valid yesterday and stale today; posting a debit past a limit that the risk engine has since lowered; activating a corporate account whose UBO chain was never completed. In every payments stack today, the ledger and the compliance engine live in different systems and reconcile after the fact. The gap between them is glue code, and glue code only "usually" gets it right. *Usually* is what fails an examination.

AtomicFi closes the gap by turning correctness into **invariants that cannot be violated**. The screening gate, the ledger post, the limit check, and the rolling-window balance update all live inside the same Postgres transaction; if any one would violate an invariant, all of them roll back. You cannot move money for a sanctioned party. You cannot post past a limit. You cannot activate a corporate without a complete UBO chain. Not as a policy — as a property of the database.

That is the product, and it is open source so the part of the stack that decides whether money is allowed to move can be read line by line, on your own infrastructure.

---

## What it does

One system. Two jobs it does very well.

### Job 1 — Compliance as first-class state

AtomicFi stores every compliance artifact a regulator or examiner would ask for:

- **`LegalEntity`** — the identity record (name, DOB, tax ID, LEI, registered address). All PII encrypted at rest.
- **`AccountHolder`** — the MDM subject, linked to its `LegalEntity`, with `kyc_status`, `risk_level`, enabled currencies. ISO 20022 `acmt:007` / `acmt:019`.
- **`BeneficialOwner`** — the UBO chain. Enforces the FinCEN CDD Rule (31 CFR §1010.230): ≥25% ownership threshold and at least one control person. Incomplete chain blocks corporate activation.
- **`KycRequirement`** — gating rules at four scopes (account holder, counterparty, payment account, beneficial owner). Covers FATF Rec 10 (CDD), Rec 16 (Wire Transfer Rule), Rec 19 (Higher-risk countries / EDD), Rec 24 (UBO Transparency).
- **`ComplianceScreening`** — OFAC, PEP, AML, adverse media. Integrates Moov Watchman against SDN / EU / UN consolidated lists. Every hit stored as a `SanctionsMatch` row with dedup across re-screenings (false-positive qualifier, list version at time of match).
- **`Document`** — uploaded identity and compliance files. Passive record; status lives in `KycRequirement`.

**ISO 20022 message families covered:** `acmt` (account management), `pain` (payment initiation), `pacs` (clearing/settlement), `camt` (cash management/statements), `auth` (regulatory reporting). If a regulator asks for a `camt:053` statement, it is generated from the data model directly.

### Job 2 — A proper double-entry ledger, in the same database

- **`Ledger`** — one per currency per account holder.
- **`LedgerAccount`** — hierarchical (`MASTER → DEBIT/CREDIT → PAIR`). Self-referential with a materialised ancestor path for O(1) ancestor lookup.
- **`LedgerEntry`** — the debit or credit posting. Every entry carries a snapshot of the risk-engine limit at time of posting.
- **`LedgerAccountBalance`** — per-day rolling totals (daily / weekly / monthly / YTD), trigger-maintained. CHECK constraints enforce that the rolling total never exceeds the last known limit.

The ledger understands risk classification. A low-risk account gets a $50K/day master limit; a high-risk one gets $5K/day. Counterparties carry their own debit and credit limits. The effective limit on any leaf account is `min(master, counterparty, screening_pair_result)`. The hierarchy enforces this by construction.

---

## Why "atomic" is the whole pitch

The database is PostgreSQL 17 with row-level security for multi-tenancy and a single trigger (`propagate_ledger_entry_to_balances`) that, on every entry post, updates the direct account's balance and every ancestor's balance and upserts the rolling-period rows in the same transaction. CHECK constraints fire synchronously.

If a limit is violated, the whole transaction rolls back — entry, balance, rolling totals, everything. You cannot move money for a sanctioned party, even accidentally, because the screening gate is in the same transaction as the ledger post. **No nightly reconciliation. No Tuesday-vs-Wednesday drift.**

---

## Where AtomicFi sits alongside other systems

AtomicFi is not trying to replace the systems already doing parts of this well. It sits **alongside** them and provides the invariant layer underneath:

| Adjacent system | What it provides | What AtomicFi adds |
|-----------------|------------------|--------------------|
| **TigerBeetle** | Atomic accounting | Compliance state — screening, KYC gates, UBO chains, audit artifacts — inside the same transaction |
| **Alloy / Sardine / ComplyAdvantage** | KYC/KYB/AML orchestration | A ledger that *honours* the decision inside the same transaction as the money movement |
| **Modern Treasury / Increase** | Ledger + payment ops | FATF-aligned compliance scopes, OFAC screening welded to posting, UBO enforcement at the schema level |
| **Marqeta / Unit** | Issuing-focused BaaS | The compliance-to-ledger substrate underneath the issuing layer |
| **Stripe / Adyen** | Card acceptance, payouts | Your own books and your own compliance state, instead of renting them |

The boundary is consistent: each of these systems produces a *decision* or a *posting*. Today the engineer writes glue to make sure the decision is still valid when the posting commits. AtomicFi removes the glue — both halves move into the same Postgres transaction, and the invariant is enforced by the database.

Because the invariants live in the code that decides whether money is allowed to move, that code has to be readable. AtomicFi is MIT-licensed so the enforcement logic can be audited end-to-end on your own infrastructure, without negotiating with a vendor or trusting a black box.

---

## Status

- **Core domain model complete.** All compliance and ledger contexts implemented end-to-end: LegalEntity, AccountHolder, BeneficialOwner, ComplianceScreening, Counterparty, Ledger, LedgerAccount, LedgerEntry, LedgerAccountBalance, KycRequirement, Document, PaymentAccount, Transaction, AccountActivitySnapshot, PartyActivitySnapshot, RiskClassification, LegalEntityChangeEvent.
- **Tests passing** against the full domain model — ExUnit, no mocks, real PostgreSQL.
- **Full REST API with OpenAPI spec** at `/api/openapi`, Scalar UI at `/api/docs`. Agent-readable surface live end-to-end.
- **Multi-tenant from day one** — Postgres row-level security via `def_with_rls_and_logging/3`. Every query is tenant-scoped by construction.
- **Sanctions screening operational** — OFAC/SDN/EU/UN consolidated lists via Moov Watchman (run alongside). Hits dedup across re-screenings with list-version-at-time-of-match stored for audit.
- **Atomic ledger trigger** (`propagate_ledger_entry_to_balances`) live — ancestor path propagation + rolling-window balance upserts in a single transaction, CHECK-constraint-enforced.
- **UBO enforcement** — FinCEN CDD ≥25% threshold and control-person requirement enforced at the schema level; incomplete chains block corporate activation.

### Next up

- **k6 load tests against native PostgreSQL** — performance benchmarking. Goal: stay in the same performance band as TigerBeetle while doing compliance gating inside the transaction.

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

BeneficialOwner                         ← FinCEN CDD §1010.230 + FATF Rec 24
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
  field :tax_id                         ← SSN / EIN / TIN (encrypted at rest)
  field :address_*                      ← KYC address verification
  field :lei                            ← ISO 17442 Legal Entity Identifier

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
  embeds_one  :contact_data             ← WatchmanContact (typed JSONB)
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

**Balance trigger**: every `ledger_entries` `INSERT`/`UPDATE(voided)` fires `propagate_ledger_entry_to_balances` — updates `ledger_accounts.balance` and upserts `ledger_account_balances` rows for the direct account AND all ancestors (via materialized `ancestor_ids`). CHECK constraints on `ledger_account_balances` enforce limits from the risk engine.

---

## Compliance Coverage

| Regulation | Enforcement |
|-----------|-------------|
| **FATF Rec 10** — Customer Due Diligence | `ComplianceScreening` `:account_holder` scope + `KycRequirement` gate account activation |
| **FATF Rec 16** — Wire Transfer Rule (incl. VASP Travel Rule, 2019 guidance) | `:payment_account`-scope `KycRequirement` gates individual payment instruction |
| **FATF Rec 19** — Higher-risk countries / EDD | High-risk accounts trigger `:counterparty`-scope screening and EDD requirements |
| **FATF Rec 24** — UBO Transparency | `BeneficialOwner` chain must be complete and verified; incomplete UBO blocks `AccountHolder` activation |
| **FinCEN CDD Rule** (31 CFR §1010.230) | `ownership_pct ≥ 25%` + control-person verification enforced via `BeneficialOwner` |
| **OFAC Sanctions** | Watchman (Moov) screens every entity against SDN/EU/UN lists; `SanctionsMatch` per hit with false-positive dedup across re-screenings |
| **PCI-DSS 4.0** | Bank/card details encrypted at rest via Cloak |
| **BSA Recordkeeping** (31 CFR §1010.430, 5-year retention) | `ComplianceScreening` + `SanctionsMatch` + `BlocklistMatch` provide the audit trail |

---

## ISO 20022 Message Coverage

All ISO 20022 messages for this domain are constructable from the data model:

| ISO Message | Purpose | Datasets Required |
|-------------|---------|-------------------|
| acmt:007 | Account Opening | AccountHolder + LegalEntity + BeneficialOwner + KycRequirement + Document |
| acmt:008 | Additional Info Request | KycRequirement + Document |
| acmt:019 | Account Closing | AccountHolder + LedgerAccount |
| pain:001 | Credit Transfer Initiation | Transaction + Counterparty + LegalEntity + LedgerAccount |
| pain:002 | Payment Status Report | Transaction |
| pacs:008 | FI Credit Transfer | Transaction + LedgerAccount |
| pacs:002 | FI Payment Status | Transaction |
| pacs:004 | Payment Return | Transaction + LedgerEntry |
| camt:052 | Account Report (intraday) | LedgerAccount + LedgerEntry + AccountActivitySnapshot |
| camt:053 | Account Statement | LedgerAccount + LedgerEntry + AccountActivitySnapshot |
| camt:054 | Debit/Credit Notification | Transaction |
| camt:060 | Account Reporting Request | LedgerAccount |
| auth:018 | Risk Classification Report | RiskClassification + ComplianceScreening |
| camt:998 | Proprietary Message (sanctions screening) | ComplianceScreening + SanctionsMatch |

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

### `chain_screening` (automatic on create)

Creating any AccountHolder, BeneficialOwner, or Counterparty automatically enqueues an Oban compliance screening job (`chain_screening: true` by default):

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

### Multi-tenancy (RLS)

Every domain record is scoped to `tenant_id`. Row-level security enforced at the repo level via `AtomicFi.LoggerMacro.def_with_rls_and_logging/3`.

### Background jobs (Oban)

| Queue | Worker | Trigger |
|-------|--------|---------|
| `compliance_screening` | `ScreeningWorker` | `chain_screening: true` on create, or manual screen action |
| `compliance_screening` | rolling-window rescreening | scheduled rescreens of existing AccountHolders, BeneficialOwners, and Counterparties against the latest Watchman list versions — every match writes a fresh `SanctionsMatch` row with the list version at time of match, so changes between screenings are visible in the audit trail |

### PostgreSQL trigger — balance propagation

`propagate_ledger_entry_to_balances` fires on every `ledger_entries` `INSERT` or `UPDATE` (when `status → :voided`):

1. Computes debit/credit delta and collects `ancestor_ids` from the direct account.
2. Updates `ledger_accounts.balance` for direct account + all ancestors in one `UPDATE WHERE id = ANY(v_account_ids)`.
3. Upserts one `ledger_account_balances` row per account per day — stores cumulative daily/weekly/monthly/yearly debit+credit totals.
4. Copies limit snapshots from the entry's `*_limit_at_entry` fields to `last_*_limit` columns on the balance row.
5. CHECK constraints on `ledger_account_balances` enforce `last_*_limit IS NULL OR balance_total <= last_*_limit`.

### OpenAPI schema pattern (ExOpenApiUtils)

Schemas use `open_api_schema` annotations to auto-generate `*Request` / `*Response` structs:

- `AccountHolder` → `AccountHolderRequest` (writeOnly fields excluded) + `AccountHolderResponse` (readOnly fields only)
- `readOnly: true` → field appears only in Response struct (server-generated: `id`, timestamps)
- `writeOnly: true` → field appears only in Request struct (sensitive input: passwords, tokens)
- No flag → field appears in both Request and Response structs
- Controllers receive typed `%AccountHolderRequest{}` structs — no map conversion needed
- `ExOpenApiUtils.Changeset.cast/3` handles `Mapper.to_map` internally — pass the struct directly to `changeset/2`

### TypeScript workspace

The TS side of the repo is a **pnpm workspace** with one published-shaped SDK package and a small number of internal consumers. Everything downstream of Phoenix is regenerated from the OpenAPI spec.

```
packages/sdk/                    @atomic-fi/sdk
  spec/openapi.yaml              ✋ committed snapshot
  generated/                     🤖 openapi-ts (gitignored)
  src/auth.ts                    ✋ buildBearerSdk, mintSecondaryTenant, …
  src/index.ts                   ✋ barrel

integration-tests/               atomic-fi-integration-tests
  src/env.ts                     ✋ TARGET_ENV={local|hh|prod}
  src/state.ts                   ✋ test-only state
  tests/<resource>.test.ts       ✋ vitest specs

api-docs/        (planned)       Docusaurus 3 + Scalar
  docs/cookbook/*.mdx            🤖 generated from vitest specs
  src/components/cookbook/       ✋ live React demos
  static/openapi.yaml            🤖 copy of packages/sdk/spec

sample-react/    (planned)       reference UI
```

**Dependency rule.** All consumers depend on `@atomic-fi/sdk` via `workspace:*` — no `file:` paths, no TS path aliases, no Nx project graph. `pnpm install` symlinks `node_modules/@atomic-fi/sdk` to `packages/sdk/`; consumers `import` it by package name like any npm dep. Internal-to-a-package imports use plain relative paths (`./env`, `./state`).

```
                    ┌─────────────────────┐
                    │   @atomic-fi/sdk    │
                    └──────────┬──────────┘
                               │ workspace:*
         ┌─────────────────────┼─────────────────────┐
         ▼                     ▼                     ▼
  integration-tests/      api-docs/            sample-react/
       (vitest)         (Docusaurus)             (reference)

      An @atomic-fi/agent (planned) reads ALL of the above from the
      filesystem as a corpus, not as npm imports — it assembles new
      financial-services apps from cookbooks + sample-react as
      raw material.
```

**Why pnpm workspace and not Nx.** Four internal packages, loose coupling, the SDK wants to be publishable to npm later. Nx pays off above ~30 packages with a heavy build graph; for this size it's over-engineering. Same shape as `platform-sdk`.

**Code generation boundaries.** Three artifacts are generated and must never be hand-edited:

| File | Generated by | Source of truth |
|---|---|---|
| `packages/sdk/spec/openapi.yaml` | `mix openapi.spec.yaml --spec AtomicFiApi.ApiSpec` | `lib/atomic_fi_api/` |
| `packages/sdk/generated/**` | `pnpm sdk:build` (openapi-ts) | `packages/sdk/spec/openapi.yaml` |
| `priv/repo/.bootstrap_creds.json` | `mix atomic_fi.dump_bootstrap_creds` | seed_migrations |

The cookbook MDX (planned) is the third generated artifact — produced by `vitest-to-mdx` from the green vitest specs in `integration-tests/`.

---

## Getting Started

### Prerequisites

- **Erlang**: 27.3.3
- **Elixir**: 1.18.3-otp-27
- **PostgreSQL**: 17.2
- **Watchman** (sanctions screening): `make run-watchman` (pulls `moov/watchman:v0.61.1`)

See `.tool-versions` for exact versions.

### Setup

```bash
# Install dependencies
mix deps.get

# Create DB, run migrations, seed
mix ecto.setup

# Start Watchman (sanctions screening + custom watchlist)
make run-watchman

# Ingest the custom watchlist into Watchman
curl -X POST http://localhost:8084/v2/ingest/custom_watchlist \
  -H "Content-Type: application/octet-stream" \
  --data-binary @custom-watchlist.jsonl

# Start server
mix phx.server
```

**Visit:**

- **API Docs**: http://localhost:4100/api/docs
- **OpenAPI Spec**: http://localhost:4100/api/openapi

### Verify Watchman

```bash
# Search sanctions lists (OFAC, CSL, UN, FinCEN 311)
curl -s "http://localhost:8084/v2/search?name=Nicolas+Maduro&type=person&limit=3"

# Search custom watchlist
curl -s "http://localhost:8084/v2/search?name=Viktor+Petrov&source=custom_watchlist&type=person"

# Search custom watchlist (organization)
curl -s "http://localhost:8084/v2/search?name=Golden+Dragon+Trading&source=custom_watchlist"
```

### Environment variables

```bash
DATABASE_URL=ecto://postgres:postgres@localhost/atomic_fi_dev
SECRET_KEY_BASE=generate_with_mix_phx_gen_secret
PHX_HOST=localhost
PORT=4100

# Watchman sanctions screening service
WATCHMAN_BASE_URL=http://localhost:8084

# Optional: tenant seed
TENANT_NAME=my-fintech
ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=change_me_in_production
```

---

## Development

```bash
# Run all tests (494 tests, 0 failures)
mix test

# Run specific domain tests
mix test test/atomic_fi/account_holder_context_test.exs
mix test test/atomic_fi/ledger_account_balance_context_test.exs

# Quality checks
mix format
mix credo --strict
mix compile --warnings-as-errors
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
| Compliance screening | Moov Watchman v0.61.1 (OFAC/SDN/CSL/UN/FinCEN 311 + custom watchlists) |
| Auth | bcrypt + TOTP 2FA + API keys |
| Pagination/filtering | Flop |
| Testing | ExUnit (DataCase + ConnCase, no mocks) |
| CI/CD | GitHub Actions (test + quality + Docker) |

---

## Use-case walkthrough toolchain (Claude Code)

The `.claude/` directory ships a small toolchain for producing demo-ready, regression-tested walkthroughs of the 5 fixed business use-cases — `setup-platform`, `onboard`, `transact`, `respond-to-aml-document-request`, `add-documents`.

The pipeline is **one interactive skill** that drives the API and **three transformation agents** that consume the resulting test + recordings.

| Component | Kind | Role |
|---|---|---|
| `usecase-vitest` | Skill (`/usecase-vitest <slug>`) | Human-led API session. Authors and debugs `integration-tests/tests/cookbook/<slug>.test.ts`, captures `integration-tests/recordings/<slug>/*.jsonl` for every API call, fixes bugs in-session via tidewave + GPG-signed `fix:` commits. Default behavior on a broken step is investigate-and-fix (no GH issues unless asked). |
| `vitest-to-mdx` | Agent | Pure transform. Reads the test + recordings, writes `api-docs/docs/cookbook/<slug>.mdx` (Docusaurus, markdown only). Bootstraps `api-docs/` on first run. |
| `vitest-to-bruno` | Agent | Pure transform. Reads the test + recordings, writes `bruno/<slug>/` — a runnable Bruno collection with chained vars and asserts. Verifies green via `bru run` before committing. |
| `vitest-to-react` | Agent (placeholder) | Future. Will emit interactive React demo pages for `atomicfi-example-web/`, modelled on [furever.dev](https://www.furever.dev/). Not implemented yet. |
| `e2e-sdk` | Skill (`/e2e-sdk`) | Broad regression E2E coverage of the full API using a typed SDK generated by `@hey-api/openapi-ts` from a committed `integration-tests/spec/openapi.yaml`. One spec per controller — CRUD + pagination + RLS isolation + hardcoded sanctions fixtures (Watchman is a prereq). Multi-env: `local`, `hh` (`atomicfi-hh.alvera.ai`), `prod`. One bearer-token bootstrap per `runId`, all specs share. Stays out of `lib/` — bug fixes happen via `usecase-vitest` or by the human. |

**Cookbook flow** (5 fixed use-cases, demo-driven):

```
/usecase-vitest onboard
  ├─ author + debug integration-tests/tests/cookbook/onboard.test.ts (interactive)
  ├─ vitest goes green
  └─ fan out (parallel):
       ├─ vitest-to-mdx    → api-docs/docs/cookbook/onboard.mdx
       └─ vitest-to-bruno  → bruno/onboard/
```

**Regression flow** (full API coverage):

```
/e2e-sdk
  ├─ TARGET_ENV=local pnpm sdk:refresh   # spec snapshot + hey-api codegen
  ├─ scaffold tests/e2e/<resource>.test.ts (CRUD + RLS + sanctions fixtures)
  └─ TARGET_ENV={local|hh|prod} pnpm test:e2e
```

The two suites share `integration-tests/` and the `runId` state model. Cookbook tests live in `tests/cookbook/`, E2E regression tests in `tests/e2e/`. Recordings are committed; generated SDK and `vitest-state/` are gitignored. Session logs at `.walkthrough-sessions/` (cookbook only) are gitignored.

---

## Contributing

AtomicFi is open source under the MIT license. Issues and PRs welcome.

Before committing:

1. `mix format && mix credo --strict && mix test`
2. GPG-sign all commits (`git commit -S`)
3. Conventional commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:` (release-please consumes these)

---

## License

Licensed under the [MIT License](LICENSE).
