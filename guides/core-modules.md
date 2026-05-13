# Core Modules

`atomic-fi` is an OSS Phoenix **payments compliance platform** — a white-label
backend any neobank, BaaS, or fintech can deploy as their compliance SoR.
Primitives mirror **FATF** and **ISO 20022** so regulatory mapping is mechanical.
The platform is **API-first** — no LiveView UI.

---

## Domains

| Domain | Contexts | Owns |
|---|---|---|
| **Identity & Auth** | `Tenant`, `User`, `Role`, `ApiKey`, `Session` | Multi-tenancy partition, RBAC, bearer auth. |
| **Parties** | `AccountHolder`, `Counterparty`, `LegalEntity`, `BeneficialOwner` | MDM subjects + PII container + FinCEN CDD chain. |
| **Compliance Ops** | `ComplianceScreening`, `Blocklist`, `KycRequirement`, `Document`, `RiskClassification` | Screening lifecycle, sanctions/blocklist hits, KYC obligations + evidence, risk tiers. |
| **Payment Ledger** | `PaymentAccount`, `Ledger`, `LedgerAccount`, `LedgerEntry`, `Transaction` | ISO 20022 instruments + double-entry bookkeeping with DB-enforced velocity limits. |
| **Snapshots** | `AccountActivitySnapshot`, `PartyActivitySnapshot` | Periodic activity rollups used by the rule engine. |
| **External engines** | `Watchman` client, `ZenRule` client | Sanctions lookups + decision rules. Transport + domain `Behaviour` split — Mox seams at the domain layer. |

Per-context implementation status (Schema / Docs / Tests / RLS / API /
Vitest / Bruno) lives in [`capability-matrix.md`](./capability-matrix.md).

---

## Personas

API-only — three consumers:

1. **Platform operator** — bearer-session, elevated role; configures tenants,
   roles, blocklists, KYC templates, rules.
2. **Integrator** (BaaS / neobank backend) — API key; orchestrates onboarding
   (AH + LE + KYC + screening) and submits transactions.
3. **Compliance officer / auditor** — bearer-session, read-only role; queries
   screening histories, beneficial-ownership chains, ledger entries, voided
   transactions with `rejected_*` metadata.

---

## ERD

```mermaid
---
title: atomic-fi domain
---
erDiagram
    Tenant ||--|{ User : authenticates
    Tenant ||--|{ ApiKey : issues
    Tenant ||--|{ AccountHolder : owns
    Tenant ||--|{ BlocklistEntry : manages
    User }o--o{ Role : "via UserRoleMapping"

    AccountHolder ||--|| LegalEntity : "PII via"
    Counterparty  ||--|| LegalEntity : "PII via"
    AccountHolder ||--|{ Counterparty : "transacts with"
    AccountHolder ||--|{ BeneficialOwner : "CDD chain"
    Counterparty  ||--|{ BeneficialOwner : "CDD chain"

    AccountHolder ||--|{ ComplianceScreening : screened
    Counterparty  ||--|{ ComplianceScreening : screened
    AccountHolder ||--|{ KycRequirement : "open obligations"
    Counterparty  ||--|{ KycRequirement : "open obligations"
    KycRequirement ||--o{ Document : "evidence"
    AccountHolder ||--|{ RiskClassification : tiered
    Counterparty  ||--|{ RiskClassification : tiered

    AccountHolder ||--|{ PaymentAccount : owns
    Counterparty  ||--|{ PaymentAccount : "owns (external)"
    AccountHolder ||--|{ Ledger : "per currency"
    Ledger ||--|{ LedgerAccount : "chart of accounts"

    PaymentAccount ||--|{ LedgerAccount : "regime tree rooted at"
    Counterparty   ||--|{ LedgerAccount : "regime tree rooted at"

    LedgerAccount ||--|{ LedgerAccountBalance : "per-period rows"
    LedgerAccount ||--|{ LedgerEntry : "posts to"
    LedgerAccount {
        integer balance "running net, trigger-maintained"
    }

    Transaction ||--|{ LedgerEntry : "balanced pair"
    Transaction }o--|| PaymentAccount : debtor
    Transaction }o--|| PaymentAccount : creditor
```

The `LedgerAccount` subtree is a strict tree with 6 `la_type` shapes
(`*_root` + `*_regime_root` per CP / AH-PA / CP-PA branch), enforced by
PostgreSQL CHECK constraints and triggers. See
[`architecture.md`](./architecture.md) for the full tree contract.

---

## See Also

- [`architecture.md`](./architecture.md) — layered architecture + LedgerAccount tree
- [`capability-matrix.md`](./capability-matrix.md) — per-context implementation status
- [`use-cases.md`](./use-cases.md) — reference scenarios driving vitest + Bruno coverage
