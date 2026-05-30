---
name: master-suite
description: Populates the DB with 100 AH / 1k CP / 10k transactions, runs all rules sequentially, prints per-rule rollup, and suggests Lotus probes. Use whenever the user wants to "run the master suite", "test all rules", "run 10k transactions", "populate the DB for the demo", "seed for Lotus", or any phrasing that requests a full compliance correctness + scale run. Composes existing mix tasks — never auto-commits.
---

# master-suite

Two-phase run: first prove every rule fires correctly (catalog scenarios with `_expected`), then populate the DB at scale (100 AH / 1k CP / 10k Txn) for the Lotus demo.

---

## Invocation

```
/master-suite                    # full run: correctness + scale
/master-suite --seed 42          # explicit seed for deterministic scale data
```

Default seed is 42 if not specified.

---

## Workflow

```
1. PREFLIGHT    →  Check backing services.
2. CORRECTNESS  →  make test-corpus (all catalog scenarios, _expected diffs)
3. SCALE        →  Generate 10k synthetic transactions, insert sequentially
4. ROLLUP       →  Per-rule summary + overall counts
5. PROBES       →  Lotus SQL probes
6. HANDOFF      →  Summary + how to query in Lotus
```

All steps run in sequence. No parallelism, no concurrency flags.

---

## Step 1 — Preflight

```bash
curl -sf http://localhost:8084/ping && echo "Watchman: UP" || echo "Watchman: DOWN"
curl -sf http://localhost:8090/api/health && echo "ZenRule: UP" || echo "ZenRule: DOWN"
```

If either is DOWN:
> Watchman/ZenRule is down. Run `make run-backing-services` first.

Do NOT proceed with services down.

---

## Step 2 — Correctness (catalog scenarios)

```bash
make test-corpus
```

Runs `mix corpus.validate --reset` against all committed scenarios under `corpus/zen_rules/`. Each scenario has 2-5 transactions with `_expected` blocks. This proves every rule fires correctly.

**Must see:** `mismatch = 0`, `setup_error = 0`, `engine_error = 0`.

If any scenario fails, STOP and report. Do not proceed to scale.

---

## Step 3 — Scale (100 AH / 1k CP / 10k Txn)

After correctness passes, generate and insert synthetic data at scale. Use the existing synthetic generators — they produce deterministic NDJSON from a seed with no external dependencies.

Run these sequentially:

```bash
# Generate ~3,300 SAML-D-shape transactions (AML monitoring patterns)
mix corpus.generate.saml_d --synthetic --rows 3300 --seed 42 --shards 1 \
  --out tmp/corpus/master-suite/saml-d

# Generate ~3,300 AMLGentex-shape transactions (cross-border patterns)
mix corpus.generate.amlgentex --synthetic --rows 3300 --seed 42 --shards 1 \
  --out tmp/corpus/master-suite/amlgentex

# Generate ~3,400 StableAML-shape transactions (crypto/stablecoin patterns)
mix corpus.generate.stableaml --emit-corpus --txns 3400 --seed 42 \
  --out tmp/corpus/master-suite/stableaml
```

Then validate each (inserts into the `atomic_fi_corpus` schema):

```bash
mix corpus.validate tmp/corpus/master-suite/saml-d --reset
mix corpus.validate tmp/corpus/master-suite/amlgentex
mix corpus.validate tmp/corpus/master-suite/stableaml
```

**Note:** Only the first `--reset` drops the schema. Subsequent runs append to the same schema so all data coexists.

**Note:** Synthetic rows have NO `_expected` blocks — they report as `new`, not `match`/`mismatch`. This is correct. The correctness proof was Step 2; Step 3 is scale + diversity.

### Expected entity counts

The generators create AHs, CPs, and PAs proportionally to transactions:

| Generator | Txns | ~AHs | ~CPs | Pattern |
|---|---|---|---|---|
| saml_d | 3,300 | ~30 | ~300 | Traditional AML monitoring |
| amlgentex | 3,300 | ~30 | ~300 | Cross-border wire patterns |
| stableaml | 3,400 | ~40 | ~400 | Crypto wallet + stablecoin |
| **Total** | **10,000** | **~100** | **~1,000** | Mixed compliance load |

---

## Step 4 — Rollup

After all inserts complete, query the DB for the combined rollup:

```bash
psql -U postgres atomic_fi_dev -c "
SET search_path TO atomic_fi_corpus, public;
SELECT t.status, count(*) as total FROM transactions t GROUP BY t.status;
"
```

```bash
psql -U postgres atomic_fi_dev -c "
SET search_path TO atomic_fi_corpus, public;
SELECT t.rejected_rule, count(*) as blocked
FROM transactions t WHERE t.status = 'rejected'
GROUP BY t.rejected_rule ORDER BY blocked DESC;
"
```

Print:
- Overall: PASS X / BLOCK Y / FREEZE Z across ~10k transactions
- Per-rule: hits, blocked count, regulatory cite
- Entity counts: AH / CP / Txn totals

---

## Step 5 — Probes

Suggest Lotus SQL probes the officer can paste into http://localhost:4100/demo/lotus-embed/ (New → New Query):

```sql
-- Blocked transactions by rule
SELECT t.rejected_rule, count(*) as blocked
FROM transactions t WHERE t.status = 'rejected'
GROUP BY t.rejected_rule ORDER BY blocked DESC

-- Overall verdict split
SELECT t.status, count(*) as total
FROM transactions t GROUP BY t.status

-- Top blocked counterparties
SELECT le.first_name, le.last_name, le.citizenship_country,
       count(t.id) as blocked_txns, sum(t.amount) as total_blocked
FROM legal_entities le
JOIN transactions t ON t.creditor_counterparty_id = le.counterparty_id
WHERE t.status = 'rejected'
GROUP BY le.first_name, le.last_name, le.citizenship_country
ORDER BY blocked_txns DESC LIMIT 20

-- Transactions by currency
SELECT t.currency, t.status, count(*) as total
FROM transactions t
GROUP BY t.currency, t.status ORDER BY total DESC
```

> **Note:** Lotus sees `atomic_fi_corpus` via `LotusRepo` search_path (configured in `config/dev.exs`). Data persists after the run.

---

## Prerequisites

1. Backing services: `make run-backing-services` (Watchman :8084, ZenRule :8090)
2. Postgres: running and migrated
3. Catalog scenarios committed: `corpus/zen_rules/`

---

## Hard rules

- **Sequential, not parallel.** Every transaction runs one at a time.
- **Correctness before scale.** Step 2 must pass with 0 mismatches before Step 3 runs.
- **Compose existing tools.** Use `make test-corpus`, `mix corpus.generate.*`, `mix corpus.validate`. Never generate NDJSON from scratch.
- **No graceful fallbacks.** Service down → refuse to proceed. Entity failure → crash loud.
- **No auto-commit.** DB state is in `atomic_fi_corpus` schema.
- **Lotus probes are manual.** This skill suggests SQL; the officer runs them.
- **Proceed without confirmation.** Run all steps in sequence. Don't ask between steps.

---

## Reference files

- **`references/rollup-format.md`** — per-rule summary and overall rollup output format
- **`references/entity-mix.md`** — entity distribution and band architecture

## Existing infrastructure (do not duplicate)

- `lib/mix/tasks/corpus.generate.saml_d.ex` — SAML-D synthetic generator
- `lib/mix/tasks/corpus.generate.amlgentex.ex` — AMLGentex synthetic generator
- `lib/mix/tasks/corpus.generate.stableaml.ex` — StableAML generator
- `lib/mix/tasks/corpus.validate.ex` — correctness validation + insertion
- `lib/atomic_fi/corpus/synthetic_seed.ex` — deterministic RNG
- `lib/atomic_fi/corpus/scenario_runner.ex` — entity insertion engine

## Related

- [country-onboarding](../country-onboarding/SKILL.md) — adds country-specific rules before running master-suite
- [generate-rules](../generate-rules/SKILL.md) — adds regulation-based rules
- [guides/verifying_correctness.md](../../../guides/verifying_correctness.md) — the why and where
