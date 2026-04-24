# Introduction

The Payments Compliance Platform is a **System of Engagement (SoE)** for payment companies —
fintechs, PSPs, e-money institutions, neobanks — that need a compliance backbone for
KYC (Know Your Customer), KYB (Know Your Business), and AML (Anti-Money Laundering).

It sits alongside existing payment processors (Stripe, JPMC, Adyen) without replacing them,
providing structured compliance data aligned to ISO 20022 and FATF recommendations.

---

## What It Does

| Capability | Detail |
|-----------|--------|
| **KYC / KYB** | AccountHolder lifecycle — `kyc_status`, document collection, CDD gating |
| **UBO Transparency** | BeneficialOwner chain — FinCEN CDD Rule ≥25% threshold + control persons |
| **OFAC / Sanctions** | Watchman (Moov) screens against SDN/EU/UN lists; per-hit SanctionsMatch records |
| **AML Monitoring** | AccountActivitySnapshot, LegalEntityChangeEvent — FinCEN AML audit trail |
| **Payment Ledger** | Double-entry LedgerAccount hierarchy with risk-limit CHECK constraints |
| **ISO 20022** | All domain data maps to acmt, pain, pacs, camt, auth message families |
| **REST API** | OpenAPI-documented endpoints at `/api/docs` (Scalar UI) |
| **Multi-Tenancy** | All data scoped by `tenant_id` via PostgreSQL RLS |

---

## Who It's For

| Vertical | Examples |
|----------|----------|
| Fintechs | Neobanks, challenger banks, digital wallets |
| Payment Processors | PSPs, acquirers, ISO/MSPs |
| E-Money Institutions | EMIs, prepaid card issuers |
| Embedded Finance | BaaS platforms, lending, BNPL |
| Crypto / Digital Assets | VASPs, exchanges requiring Travel Rule compliance |

---

## Domain Model (Summary)

```
AccountHolder (MDM subject — acmt:007, acmt:019)
  belongs_to :legal_entity          ← ALL PII: name, DOB, tax_id, address, email, phone
  has_many   :beneficial_owners     ← UBO chain (FinCEN CDD ≥25% threshold)
  has_many   :counterparties        ← payer/payee roles (pain:001 <Dbtr>/<Cdtr>)
  has_one    :ledger                ← chart of accounts (camt:052/053)
  has_many   :compliance_screenings ← OFAC/SDN/PEP results
  has_many   :kyc_requirements      ← CDD gates
  has_many   :documents             ← identity documents
```

See the [capability matrix](capability-matrix.md) for per-context implementation status.

---

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Language | Elixir 1.18 / OTP 27 |
| Web framework | Phoenix 1.8 |
| Database | PostgreSQL 17.2 with RLS + triggers |
| API documentation | OpenApiSpex + Scalar UI |
| Schema generation | ExOpenApiUtils (Request/Response auto-split) |
| Background jobs | Oban — `compliance_screening` queue |
| Compliance screening | Moov Watchman (OFAC/SDN/EU/UN lists) |
| Auth | bcrypt + TOTP 2FA + API keys |
| Testing | ExUnit (DataCase + ConnCase, no mocks) |

---

## Getting Started

1. [Getting Started](getting-started.md) — setup and configuration
2. [Architecture](architecture.md) — directory structure and design patterns
3. [API Development](api-development.md) — adding REST endpoints
4. [Testing](testing.md) — writing and running tests

API docs at `http://localhost:4001/api/docs` once the server is running.
