# Verifying the Correctness of AtomicFi

**Deterministic. Sourced. End-to-end.**

*Synthetic test data and matching screening fixtures for every compliance claim AtomicFi makes.*

---

## Why

AtomicFi makes 67 specific compliance claims, one per row in [`guides/use-cases.md`](use-cases.md). Every release, every PR, every regulator walk-through has to prove all 67 — not by screenshot, by runnable artefact.

Real customer data can't be used to test these flows: privacy, retention, jurisdictional restrictions, and the simple problem that real data doesn't reliably contain the edge cases regulators ask about. Hand-crafted fixtures don't scale past a dozen rows and never round-trip against the screening oracle — they let bugs slip through the gap between the fixture and the matcher. Existing open synthetic-payments datasets — PaySim [1], IBM AMLSim [2], AMLWorld [3], SAML-D [4], AMLGentex [5] — emphasise transaction-graph fraud labels for ML training, not regulatory verification, and don't co-emit identity, KYC state, beneficial ownership, or sanctions-match fixtures. The closest commercial peer is Change Financial's PaySim [16], a payments-testing platform aimed at processor reliability ("60,000 transaction-type variations, 10,000 TPS") rather than the compliance-claim provenance we need.

This generator does, for every claim:

- exactly the `AccountHolder` / `Counterparty` / `PaymentAccount` / `Transaction` rows that match the scenario's preconditions,
- the matching moov/watchman [9] screening-list entry — paired by a deterministic `ent_num` — so the platform's screening pipeline sees the confidence band the catalog promises,
- the expected verdict (`PASS` / `REVIEW` / `BLOCK` / `FREEZE`) carried inline on every row, so a test asserts it without re-deriving the rule.

Same `(seed, shards, pass-rate)` → byte-identical output, every run.

## What

Four NDJSON streams per shard:

| File | Rows | Embedded |
|---|---|---|
| `ah.ndjson` | one per `AccountHolder` | `legal_entity`, `beneficial_owners[]` (business AHs) |
| `pa.ndjson` | one per `PaymentAccount` | — |
| `cp.ndjson` | one per `Counterparty` | `legal_entity` |
| `txn.ndjson` | one per `Transaction` (paired ledger entries) | — |

`LegalEntity` and `BeneficialOwner` ride embedded inside their parent — same pattern as the platform's REST surface. Every row carries `_meta.target_scenario` and `_meta.expected_verdict`.

Plus a parallel set of moov/watchman-format screening CSVs for sanctions-flavoured rows:

| File | Content |
|---|---|
| `screening/sdn.csv` | OFAC SDN entries paired to corpus AH/CP rows |
| `screening/alt.csv` | Alternate-identity rows |
| `screening/add.csv` | Address rows |
| `screening/dca.csv` | Digital-currency address rows (stablecoin scenarios) |

Watchman `ent_num` is derived from `(seed, ah_or_cp_id)`, so two runs on the same seed pair the same corpus row to the same Watchman entry and the same confidence band per OFAC's *Framework for Compliance Commitments* (May 2019) [12].

What this is *not*: a distribution-fitter (those copy real data's statistics — see TabularARGN [6], Gretel [7], TabSyn [8]). The corpus is purpose-built per scenario, not a smoothing of historical data.

## How

The pipeline splits at the canonical-JSON boundary. AI handles unstructured-to-structured work (PDF → JSON, slow, manual). Mix handles structured-to-runtime work (JSON → NDJSON, deterministic, fast). Each does the work it's good at.

```
        AUTHORING  (manual, when a regulator publishes)
        ──────────────────────────────────────────────
   FATF MER PDF ──┐
   FinCEN PDF ────┼─► Claude skill: pdf-to-typology ──► one JSON file
   OFAC actions ──┤            one file per input directive
   Treasury PDFs ─┘                                      │
                                                         ▼
                                  compliance-list/extracted/<source>/...
                                                         │   PR review
                                                         ▼
                                          compliance-list/  (merged)
                                                         ▲
   peer-reviewed source corpus ──────────────────────────┤
   (OpenSanctions exports, ISO 3166 / 4217,              │
    FATF country lists, NACHA return codes [13],         │
    Stripe test PANs [14])                               │
        ──────────────────────────────────────────────
                                                         │
        SYNTHESIS  (deterministic, every test run)       │
        ──────────────────────────────────────────────│
                                                         ▼
                                          mix compliance.build
                                                         ↓
                                  compliance-db/compliance.sqlite
                                                         ↓
                                  mix alvera.gen.compliance_corpus
                                                         ↓
                          tmp/corpus/<seed>-<pass-rate>/shard_0001/
                              ah.ndjson  pa.ndjson  cp.ndjson  txn.ndjson
                              screening/sdn.csv  alt.csv  add.csv  dca.csv
                                                         ↓
                                          mix bench.seed
                                                         ↓
                                  test / benchmark / k6 consumers
```

### Authoring — AI

The `pdf-to-typology` Claude skill reads one authoritative PDF (FATF typology report, FinCEN advisory, OFAC enforcement release, US Treasury risk assessment) and writes **one canonical JSON file per input directive** into `compliance-list/extracted/<source>/<bucket>/`. Each invocation produces a manifest summarising what was extracted, what was skipped, and what was ambiguous — the artefact a human reviews. PR-gated. AI handles PDF segmentation because it's the work hardest to automate well and least likely to need to re-run on the same input.

### Authoring — peer-reviewed sources

Some sources arrive already structured: OpenSanctions consolidated dumps [10], ISO 3166-1 and 4217, FATF country lists [11], NACHA return codes [13], Stripe test PANs [14]. These don't need AI — they need PR-review curation. They land in `compliance-list/curated/<source>/...` with the same canonical JSON shape as the AI-extracted side. The `_provenance.method` field is `"ai-extracted"` vs `"peer-reviewed"`. Both feed the same compile step.

### Canonical record shape

```json
{
  "id": "fatf-typology-trade-based-ml-2024",
  "source": "FATF",
  "bucket": "typology",
  "title": "Trade-Based Money Laundering Update",
  "publication_date": "2024-03-12",
  "regulation_cites": ["FATF Recommendation 16", "BSA §1020.320"],
  "typologies": [
    {
      "id": "tbml-over-invoicing",
      "name": "Over-invoicing",
      "page_refs": ["pp. 23-27"],
      "indicators": ["Invoice value ≥200% market rate"],
      "expected_verdict": "REVIEW"
    }
  ],
  "country_tags": [{"iso": "RU", "tier": "high_risk"}],
  "_provenance": {
    "method": "ai-extracted",
    "source_url": "https://www.fatf-gafi.org/...",
    "sha256_of_source": "..."
  }
}
```

The folder layout is borrowed from Aqua Security's Trivy DB [15] — per-source canonical JSON, compiled to a fast lookup — but operated very differently. There's no scheduled refresh and no third-party distribution. The catalogue lives in this repo and refreshes when a maintainer runs the skill.

### Synthesis — Mix

| Task | Reads | Writes |
|---|---|---|
| `mix compliance.build` | `compliance-list/` (extracted + curated) | `compliance-db/compliance.sqlite` + manifest |
| `mix alvera.gen.compliance_corpus --shards N --pass-rate P --seed S` | patterns + compliance-db | `tmp/corpus/<seed>-<pass-rate>/shard_*/` NDJSON + screening CSVs |
| `mix bench.seed` | NDJSON shards | bulk-inserts via `AccountHolderContext` / `CounterpartyContext` / `PaymentAccountContext` / `TransactionContext` (RLS-scoped via `Session`) |

All three Mix tasks are pure functions of their inputs. Shard *k*'s sub-RNG is `:crypto.hash(:sha256, S ++ <<k::32>>)`. The compiled `compliance.sqlite` is gitignored; its checksum is recorded in `compliance-db/manifest.json`.

### Pattern catalogue

Patterns sit under `compliance-patterns/` organised by regulatory regime, mirroring the catalog's section structure:

```
compliance-patterns/
  01-aml-cip/
    06-kyc-in-progress.json
    07-kyc-rejected.json
    10-prohibited-holder-freeze.json
  02-ofac-sanctions/
    11-recipient-sdn.json
    11b-sdn-probable-match.json
    12-recipient-iran.json
  03-edd-geo/
    17-geo-residency-mismatch.json
  04-structuring/
    19-sub-ctr-window.json
  …
```

One pattern file per catalog row. Each declares prevalence weight, agent gates, generator function, expected verdict, and a `_compliance_refs[]` array linking back to the `compliance-list` records that justify it.

### Watchman pair-bonding

For every AH or CP whose pattern requires a sanctions match (catalog scenarios 11, 11a–e, 12–16, 29), the generator emits a moov/watchman-ingestable record [9]. `ent_num` is deterministic from `(seed, ah_or_cp_id)`. OpenSanctions Yente's `logic-v2` [10] is consulted at generation time as the band reference: each name is placed in ≥95 / 85–94 / 70–84 / 50–69 / <50 per OFAC's *Framework for Compliance Commitments* [12]. The assertion "AH should be BLOCKED, OFAC report due" reads `_meta.expected_verdict` and needs no live oracle call.

### Folder layout

```
compliance-list/                  ← canonical, source of truth
  extracted/                        AI-written (one file per directive)
    fatf/typology/trade-based-ml-2024.json
    fincen/advisory/fin-2024-a001.json
  curated/                          peer-reviewed (already structured)
    opensanctions/sdn-subset.json
    iso/3166-1.json
    nacha/return-codes.json

compliance-db/                    ← compiled lookup
  compliance.sqlite                 (gitignored)
  manifest.json                     (committed: checksums + provenance)

compliance-patterns/              ← one file per catalog row
  <regime>/<NN>-<slug>.json

tmp/corpus/                       ← gitignored generator output
  <seed>-<pass-rate>/shard_0001/
    ah.ndjson  pa.ndjson  cp.ndjson  txn.ndjson
    screening/sdn.csv  alt.csv  add.csv  dca.csv
```

Nothing lives under `priv/`. The corpus is application test data, not Phoenix-runtime data.

---

## References

[1] Lopez-Rojas, E., Elmir, A., & Axelsson, S. (2016). *PaySim: A Financial Mobile Money Simulator for Fraud Detection*. EMSS 2016. github.com/EdgarLopezPhD/PaySim

[2] IBM Research. *AMLSim*. github.com/IBM/AMLSim

[3] Altman, E., Egressy, B., Blanuša, J., & Atasu, K. (2023). *Realistic Synthetic Financial Transactions for Anti-Money Laundering Models*. NeurIPS 2023. arXiv:2306.16424. github.com/IBM/AML-Data

[4] Oztas, B. et al. (2023). *Enhancing Anti-Money Laundering: Development of a Synthetic Transaction Monitoring Dataset*. IEEE ICEBE 2023. github.com/BOztasUK/Anti_Money_Laundering_Transaction_Data_SAML-D

[5] AI Sweden, Handelsbanken & Swedbank (2024–25). *AMLGentex*. github.com/aidotse/AMLGentex; arXiv:2503.24259.

[6] Tiwald, P. et al. (2025). *TabularARGN*. arXiv:2508.00718. github.com/mostly-ai/mostlyai

[7] Gretel.ai. *gretel-synthetics*. github.com/gretelai/gretel-synthetics

[8] Mehta, V. et al. (2025). *Benchmark of Tabular Synthetic Data Generators*. Data Science Journal. doi:10.5334/dsj-2025-037

[9] Moov. *Watchman*. github.com/moov-io/watchman

[10] OpenSanctions Foundation. *Yente v5* (2024). github.com/opensanctions/yente

[11] FATF. *High-Risk Jurisdictions list*; *Recommendation 16: Wire Transfers*.

[12] U.S. Treasury OFAC (2019). *Framework for OFAC Compliance Commitments*. ofac.treasury.gov/media/16331/download

[13] NACHA. *ACH Return Codes Reference*.

[14] Stripe. *Test Card Numbers*. docs.stripe.com/testing

[15] Aqua Security. *Trivy DB & vuln-list*. github.com/aquasecurity/trivy-db; github.com/aquasecurity/vuln-list

[16] Change Financial. *PaySim — payment simulation, testing and certification*. changefinancial.com/paysim

[17] 31 USC §5324; 31 CFR §1020.320 (BSA structuring + SAR).

[18] ISO 3166-1; ISO 4217; ISO 20022.

[19] Voutila, D. *PaySim 2.x*. github.com/voutilad/PaySim
