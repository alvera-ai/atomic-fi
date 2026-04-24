# Platform Integration (System of Intelligence)

This guide describes the **optional** integration between this System of Engagement (SoE) and an upstream System of Intelligence (SoI) — specifically the Alvera Platform.

The SoE is **fully functional standalone**. Nothing in this guide is required for the core KYC/KYB/AML compliance backbone to operate. This document exists so operators who choose to connect the SoE to the Alvera Platform know what capabilities become available and how the integration is wired.

---

## Three-Tier Position

```
SoR (Legacy)          SoE (This repo)                 SoI (Alvera Platform)
────────────          ────────────────                ──────────────────────
Stripe                Payments Compliance        ───► Alvera Platform
JPMC          ──►     Platform (this repo)       │    ├── Data Activation Pipeline
Adyen                 ├── PostgreSQL (owner)     │    ├── MDM (AccountHolder resolution)
                      ├── Oban CDC outbound ─────┘    ├── Triplication (raw + tokenized)
                      └── PlatformSyncWorker ◄──────── ├── Agentic Workflows
                          (inbound sync)               ├── MCP Server
                                                       └── REST API + Scalar UI
```

The SoE runs alongside existing payment processors (SoR) and owns its own PostgreSQL database. When connected to an SoI, the SoE becomes a source of truth for compliance data while the SoI provides analytics, MDM resolution, agentic workflows, and an AI query layer.

---

## What the Alvera Platform SoI Provides

| Capability | What the SoE gets |
|-----------|-------------------|
| **Data Activation** | Platform continuously syncs SoE data into the `payments` datalake — no need to build a separate ETL |
| **MDM (Master Data Management)** | AccountHolder entity resolution across Stripe, JPMC, Adyen, and other payment sources |
| **Triplication** | Regulated (raw PII) + Unregulated (tokenized) + Tokenized (SHA-256) storage tiers — PII segregation handled automatically |
| **Compliance Screening** | OFAC/SDN, PEP, AML scoring via Watchman against public feeds — centrally maintained |
| **Agentic Workflows** | Stuck-KYC detection, OFAC escalation, payment recovery — triggered by datalake events |
| **MCP Server** | AI agents query the payments datalake without the SoE building its own AI layer |

---

## Dual-Schema / Triplication Architecture

Within the Alvera Platform, each dataset maintains three parallel representations. The SoE only needs to know about the first one — the Platform handles the triplication.

| Schema | Purpose | Access |
|--------|---------|--------|
| **Regulated** | Raw PII for humans and compliance officers | Human + authorized service accounts |
| **Unregulated (Public)** | Tokenized PII, safe for AI agents | AI agents, MCP |
| **Tokenized (SHA-256)** | Opaque hashes for joins across regulated/public | Internal pipeline |

### What Gets Tokenized

| Field | Reason |
|-------|--------|
| `legal_name`, `date_of_birth`, `tax_id` | KYC identity — FATF CDD Rec 10 |
| `nationality`, `email`, `phone` | Contact PII |
| `address_line1`, `city`, `state`, `postal_code` | KYC address verification |
| `account_number`, `routing_number`, `iban`, `card_pan` | PCI-DSS 4.0 |
| `response_content`, `extracted_fields` | KYC response data — may contain PII |
| `matched_name`, `sdn_entity_pii` | OFAC/SDN match details |
| `debtor_name`, `creditor_name`, `remittance_info` | Payment party PII (ISO 20022 RmtInf) |

### What Is NOT Tokenized (safe for AI)

| Field | Reason |
|-------|--------|
| `holder_type`, `kyc_status`, `risk_level` | Enums — not PII |
| `account_holder_number`, `ledger_account_number` | Opaque internal IDs |
| `lei` | ISO 17442 Legal Entity Identifier — public standard |
| `amount`, `currency`, `entry_type` | Transaction metadata — not PII |
| `swift_bic`, `bank_name` | Public bank identifiers |
| `screening_status`, `scope` | Workflow state — not PII |

---

## CDC Outbound to the Platform

The SoE syncs to the Platform SoI via an Oban cron job (every 5 minutes):

```
Local PostgreSQL
  └── Oban cron job (updated_at cursor)
        └── Batch changed rows since last_synced_at
              └── POST to Platform ingest endpoint
                    └── Platform: MDM Resolve → Dataset Upsert → Generate Event → Agentic Workflows
```

The ingest endpoint is configurable via environment variable. Without the Platform, the outbound cron can be disabled or pointed at a different downstream consumer.

---

## Inbound Sync from the Platform

`PlatformSyncWorker` polls the Platform's events API on a configurable schedule and writes returned results back to the local DB:

- **Compliance screening results** — AML scores, PEP flags computed on the platform side
- **MDM merges** — when AccountHolder identity resolution decides two SoE records refer to the same entity
- **Workflow outputs** — decisions made by agentic workflows (e.g., "stuck KYC needs manual review")

---

## Deployment Modes

| Mode | Description |
|------|-------------|
| **Standalone** | SoE runs alone. No SoI integration. CDC outbound is disabled. Fully functional compliance backbone with direct Watchman screening. |
| **Platform-attached** | SoE runs with CDC outbound + `PlatformSyncWorker` enabled. Gains MDM, agentic workflows, tokenized AI access, and cross-source entity resolution. |

Choose based on whether the data domain spans multiple sources (Platform-attached makes sense) or is self-contained (Standalone is simpler).

---

## References

- [ISO 20022 Message Coverage](../README.md#iso-20022-message-coverage)
- [Compliance Coverage](../README.md#compliance-coverage)
- [Domain Model](../README.md#domain-model)
