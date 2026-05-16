# Verifying the Correctness of AtomicFi

**Deterministic. Sourced. End-to-end.**

*Synthetic test data and matching screening fixtures for every compliance claim AtomicFi makes.*

---

## Why

AtomicFi makes 67 specific compliance claims, one per row in [`guides/use-cases.md`](use-cases.md). Every release, every PR, every regulator walk-through has to prove all 67 — not by screenshot, by runnable artefact.

Real customer data can't be used to test these flows: privacy, retention, jurisdictional restrictions, and the simple problem that real data doesn't reliably contain the edge cases regulators ask about. Hand-crafted fixtures don't scale past a dozen rows and never round-trip against the screening oracle — they let bugs slip through the gap between the fixture and the matcher. Existing open synthetic-payments datasets — PaySim [1], IBM AMLSim [2], AMLWorld [3], SAML-D [4], AMLGentex [5] — emphasise transaction-graph fraud labels for ML training, not regulatory verification, and don't co-emit identity, KYC state, beneficial ownership, or sanctions-match fixtures. The closest commercial peer is Change Financial's PaySim [16], a payments-testing platform aimed at processor reliability ("60,000 transaction-type variations, 10,000 TPS") rather than the compliance-claim provenance we need.

Two complementary classes of sources solve this:

1. **Peer-reviewed synthetic AML datasets** that already exist — SAML-D [4], StableAML [10], AMLGentex [5]. Bank-backed, published, with labels we can trust. Pin a few of these as upstreams; sample, map, and emit our shape.
2. **The ZenRule JDM rules themselves** — every rule under `priv/zenrule/` IS a source of truth. An LLM drafts payloads against the rule, the live rule engine verifies them, drift triggers another iteration. No external dataset needed.

Same `(seed, source, ratios)` → byte-identical output, every run. This satisfies the outcomes-analysis loop SR 11-7 requires of any BSA/AML model: input → expected → actual → commit on match [17].

## What

The deliverable per scenario is a **fixture triple** plus bulk ndjson:

```
test/support/upstream/<src>/fixtures/<scenario>/
  payload.json     ← the AccountHolder/Counterparty/PaymentAccount/Txn rows
  request.json     ← the POST /api/... body
  expected.json    ← rule-engine verdict + ledger deltas
  _label.json      ← { synthetic: true, source, regime, cite, verdict }

tmp/corpus/<seed>/<src>/                           (gitignored, regenerable)
  ah.ndjson  cp.ndjson  pa.ndjson  txn.ndjson      (FK-ordered)
  screening/sdn.csv  alt.csv  add.csv  dca.csv     (moov/watchman pair-bonded)
```

Fixture triples are kB-scale, committed, regulator-readable. Bulk ndjson is regenerable from `(seed, source)` and stays gitignored.

Every emitted row carries an embedded `_label` block — pattern slug, regime, regulatory cite, expected verdict — so `jq | sort | uniq -c` over the corpus is an SR 11-7 outcomes-analysis report by hand:

```
                                                by regime    aml-cip 200   ofac 158   …
  jq '._label | "\(.regime)\t\(.verdict)"'     by verdict   PASS 9600   REVIEW 240   BLOCK 158
                                                by cite      31 CFR §1020.220 ×42   …
                                                coverage     12/67 catalog rows hit
```

Watchman `ent_num` is derived from `(seed, ah_or_cp_id)`, so two runs on the same seed pair the same corpus row to the same Watchman entry and the same confidence band per OFAC's *Framework for Compliance Commitments* (May 2019) [12].

What this is *not*: a distribution-fitter (those copy real data's statistics — see TabularARGN [6], Gretel [7], TabSyn [8]). The corpus is purpose-built per scenario, not a smoothing of historical data.

## How

```
   RAW UPSTREAMS  (outside the repo, $ATOMIC_FI_CORPUS_ROOT, GB-scale)
   ───────────────────────────────────────────────────────────────────
   stableaml/StableAML.csv          ← FINOS Labs DTCC Hackathon 2025 (1 MB)
   saml-d/SAML-D.csv                ← Kaggle (12 MB)
   amlgentex/transactions.parquet   ← maintainer-generated snapshot

                       │
                       ▼ (reseed-<src> skill, one-time, manifest sha-pinned)

   PER-SOURCE GENERATE  (read raw → sample → map → emit, one pass)
   ───────────────────────────────────────────────────────────────
   mix corpus.generate.stableaml    --wallets N  --cybercrime P  --seed S
   mix corpus.generate.saml_d       --rows N     --suspicious P  --seed S
   mix corpus.generate.amlgentex    --rows N     --alerts P      --seed S

                       │  (parallel path, no external dataset)
                       ▼

   RULE-AS-SOURCE  (LLM-iterate against rule engine)
   ──────────────────────────────────────────────────
   skill: corpus-from-rule
     read priv/zenrule/<rule>.json
     LLM drafts payloads matching declared verdict bands
     mix corpus.validate runs payloads against rule-engine docker
     if actual ratio drifts > tolerance, iterate (--iter cap)
     commit fixtures under test/support/upstream/<rule_id>/fixtures/

                       │
                       ▼

   FIXTURES + BULK NDJSON
   ──────────────────────
   test/support/upstream/<src>/fixtures/<scenario>/...   (committed)
   tmp/corpus/<seed>/<src>/*.ndjson                       (gitignored)

                       │
                       ▼

   VERIFICATION  (shared, dataset-agnostic)
   ────────────────────────────────────────
   mix corpus.validate "<regex>"
     walks fixtures matching regex
     POSTs payload to rule-engine docker
     diffs actual against expected.json
     emits markdown drift report

   mix bench.seed
     reads tmp/corpus/<seed>/*.ndjson
     bulk-inserts via AccountHolderContext / CounterpartyContext /
     PaymentAccountContext / TransactionContext (RLS-scoped via Session)
```

### Raw lives outside the repo

```elixir
config :atomic_fi, :corpus_root,
  System.get_env("ATOMIC_FI_CORPUS_ROOT") ||
    Path.join(System.user_home!(), ".local/share/atomic-fi/corpus")
```

Datasets vary from 1 MB (StableAML) to GB-scale (AMLGentex parquet, AMLWorld). Pinning by sha256 in a small committed `manifest.json` per source is enough; the bytes don't belong in our git history. Each `reseed-<src>` skill is idempotent — checks the manifest, skips if the sha matches.

### Per-source ownership

Each upstream owns three artefacts that travel together. Adding a new upstream = one skill + one mix task + one raw folder. Shared `corpus.validate` stays untouched.

| Upstream      | Reseed skill        | Generate task                    | Raw location                                       |
|---------------|---------------------|----------------------------------|----------------------------------------------------|
| rule files    | `corpus-from-rule`  | (rule-as-source path)            | `priv/zenrule/<rule>.json`                         |
| StableAML [10]| `reseed-stableaml`  | `mix corpus.generate.stableaml`  | `$CORPUS_ROOT/stableaml/StableAML.csv`             |
| SAML-D [4]    | `reseed-saml-d`     | `mix corpus.generate.saml_d`     | `$CORPUS_ROOT/saml-d/SAML-D.csv`                   |
| AMLGentex [5] | `reseed-amlgentex`  | `mix corpus.generate.amlgentex`  | `$CORPUS_ROOT/amlgentex/transactions.parquet`      |

AMLWorld [3] is deferred — its 180M-txn LI-Large would force Kaggle-CLI integration and Parquet handling, neither of which pays off until SAML-D's typologies and AMLGentex's configurable graphs are exhausted.

### Per-source generate flow

Each `corpus.generate.<src>` task does three things in one pass:

1. **Sample** — RNG-seeded selection of N rows from the raw upstream respecting per-source ratio knobs (`--suspicious` for SAML-D, `--cybercrime` for StableAML, `--alerts` for AMLGentex).
2. **Map** — translate the upstream's column shape into atomic-fi's `AccountHolder` / `Counterparty` / `PaymentAccount` / `Transaction` schema.
3. **Emit** — write ndjson streams in FK order (AH → CP → PA → Txn), plus a fixture triple per labelled scenario in the sample.

Ratio knobs are deliberately dataset-specific. SAML-D's "suspicious" label is not StableAML's "cybercrime" classification. Forcing a shared abstraction loses signal we want auditable.

### Rule-as-source

A JDM rule under `priv/zenrule/transaction-screening/<rule_id>.json` is an upstream in the same sense as SAML-D. The `corpus-from-rule` skill:

1. Reads the rule, derives expected verdict bands from its nodes.
2. LLM drafts N payloads matching the declared pass-rate.
3. Invokes `mix corpus.validate` — payloads POST to the rule-engine docker.
4. If the actual `{PASS,REVIEW,BLOCK,FREEZE}` ratio drifts from expected by more than tolerance, the diff feeds back into the LLM and step 2 repeats up to a `--iter` cap.
5. On convergence, fixtures land at `test/support/upstream/<rule_id>/fixtures/`.

This closes the SR 11-7 outcomes-analysis loop with no external dataset — the rule IS the test oracle [17].

### Watchman pair-bonding

For every AH or CP whose pattern requires a sanctions match (catalog scenarios 11, 11a–e, 12–16, 29), the generator emits a moov/watchman-ingestable record [9]. `ent_num` is deterministic from `(seed, ah_or_cp_id)`. OpenSanctions Yente's `logic-v2` [11] is consulted at generation time as the band reference: each name is placed in ≥95 / 85–94 / 70–84 / 50–69 / <50 per OFAC's *Framework for Compliance Commitments* [12]. The assertion "AH should be BLOCKED, OFAC report due" reads `_label.verdict` and needs no live oracle call.

### Folder layout

```
$ATOMIC_FI_CORPUS_ROOT/             ← outside repo, GB-scale
  stableaml/StableAML.csv
  saml-d/SAML-D.csv
  amlgentex/transactions.parquet

test/support/upstream/              ← committed
  stableaml/manifest.json
  stableaml/fixtures/<scenario>/{payload,request,expected,_label}.json
  saml-d/manifest.json
  saml-d/fixtures/<scenario>/...
  amlgentex/manifest.json
  amlgentex/fixtures/<scenario>/...
  <rule_id>/fixtures/<scenario>/...

tmp/corpus/<seed>/<src>/            ← gitignored, regenerable
  ah.ndjson  cp.ndjson  pa.ndjson  txn.ndjson
  screening/sdn.csv  alt.csv  add.csv  dca.csv
```

Nothing new lives under `priv/`. The corpus is application test data, not Phoenix-runtime data.

### Implementation order

1. `corpus-from-rule` skill + `mix corpus.validate` — proves the verdict-verified loop end-to-end with no external dataset.
2. `reseed-stableaml` + `mix corpus.generate.stableaml` — smallest upstream (1 MB), FINOS-hosted, no Kaggle auth.
3. `reseed-saml-d` + `mix corpus.generate.saml_d` — Kaggle CLI auth, 12 MB, 17 suspicious typologies.
4. `reseed-amlgentex` + `mix corpus.generate.amlgentex` — Python sim run, snapshot committed; defer until the prior three leave gaps.

---

## References

[1] Lopez-Rojas, E., Elmir, A., & Axelsson, S. (2016). *PaySim: A Financial Mobile Money Simulator for Fraud Detection*. EMSS 2016. github.com/EdgarLopezPhD/PaySim

[2] IBM Research. *AMLSim*. github.com/IBM/AMLSim

[3] Altman, E., Egressy, B., Blanuša, J., & Atasu, K. (2023). *Realistic Synthetic Financial Transactions for Anti-Money Laundering Models*. NeurIPS 2023. arXiv:2306.16424. github.com/IBM/AML-Data

[4] Oztas, B. et al. (2023). *Enhancing Anti-Money Laundering: Development of a Synthetic Transaction Monitoring Dataset*. IEEE ICEBE 2023. github.com/BOztasUK/Anti_Money_Laundering_Transaction_Data_SAML-D

[5] AI Sweden, Handelsbanken & Swedbank (2024–25). *AMLGentex*. github.com/aidotse/AMLGentex; arXiv:2506.13989.

[6] Tiwald, P. et al. (2025). *TabularARGN*. arXiv:2508.00718. github.com/mostly-ai/mostlyai

[7] Gretel.ai. *gretel-synthetics*. github.com/gretelai/gretel-synthetics

[8] Mehta, V. et al. (2025). *Benchmark of Tabular Synthetic Data Generators*. Data Science Journal. doi:10.5334/dsj-2025-037

[9] Moov. *Watchman*. github.com/moov-io/watchman

[10] FINOS Labs (2025). *StableAML*, in the *OpenAML* DTCC Hackathon submission. github.com/finos-labs/dtcch-2025-OpenAML; arXiv:2602.17842.

[11] OpenSanctions Foundation. *Yente v5* (2024). github.com/opensanctions/yente

[12] U.S. Treasury OFAC (2019). *Framework for OFAC Compliance Commitments*. ofac.treasury.gov/media/16331/download

[13] NACHA. *ACH Return Codes Reference*.

[14] Stripe. *Test Card Numbers*. docs.stripe.com/testing

[15] Aqua Security. *Trivy DB & vuln-list*. github.com/aquasecurity/trivy-db; github.com/aquasecurity/vuln-list

[16] Change Financial. *PaySim — payment simulation, testing and certification*. changefinancial.com/paysim

[17] Federal Reserve & OCC (2011). *SR 11-7: Supervisory Guidance on Model Risk Management*. federalreserve.gov/supervisionreg/srletters/sr1107.htm

[18] 31 USC §5324; 31 CFR §1020.320 (BSA structuring + SAR).

[19] ISO 3166-1; ISO 4217; ISO 20022.

[20] Voutila, D. *PaySim 2.x*. github.com/voutilad/PaySim
