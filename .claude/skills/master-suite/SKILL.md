---
name: master-suite
description: Runs the full compliance rule catalog (10 scenarios) through the existing corpus pipeline at scale, prints per-rule coverage and overall rollup, and suggests Lotus probe questions. Use whenever the user wants to "run the master suite", "test all rules at scale", "run 10k transactions", "seed for the compliance demo", "run corpus.bench", or any phrasing that requests a large-scale multi-rule test run. Composes existing make targets + mix tasks — never auto-commits.
---

# master-suite

Run all 10 catalog scenarios through the existing corpus pipeline, report per-rule coverage and overall rollup, suggest Lotus probes. Composes `make test-corpus`, `make bench`, and the `corpus.generate.*` tasks — does not generate its own NDJSON.

---

## Invocation

```
/master-suite                          # correctness (10/10 rules, ~50 txns)
/master-suite --scale 1000             # bench at 1000 VUs (~5k-10k txns)
/master-suite --scale 10000            # bench at 10000 VUs (~50k-100k txns)
/master-suite --synthetic --rows 10000 # synthetic corpus at 10k rows
```

---

## Workflow

```
1. PREFLIGHT   →  Check backing services (Watchman :8084, ZenRule :8090).
                   If down: tell user to run `make run-backing-services`.
                   Do NOT proceed — services are required.

2. CORRECTNESS →  make test-corpus
                   Runs `mix corpus.validate --reset` against all 10 committed
                   catalog scenarios under corpus/zen_rules/.
                   Verifies 10/10 rule coverage with _expected diffs.

3. SCALE       →  make bench BENCH_LEVELS=<N>
                   (only if --scale was requested)
                   k6-style VU sweep. Each VU runs one of 10 scenarios (round-robin).
                   Produces a markdown report under benchmarks/.

4. ROLLUP      →  Read the validate/bench output. Print:
                   - Per-rule summary (hits, verdicts, blocked counts, regulatory cite)
                   - Overall rollup (PASS/REVIEW/BLOCK/FREEZE, coverage X/10)
                   - Accuracy summary (match/mismatch/new/setup_error/engine_error)

5. PROBES      →  Suggest 5-6 Lotus probe questions based on what fired.

6. HANDOFF     →  Summary of what was run + how to interpret results.
```

---

## Step 1 — Preflight

Check service health before running anything:

```bash
curl -sf http://localhost:8084/v2/health && echo "Watchman: UP" || echo "Watchman: DOWN"
curl -sf http://localhost:8090/health && echo "ZenRule: UP" || echo "ZenRule: DOWN"
```

If either is DOWN, tell the user:
> Watchman/ZenRule is down. Run `make run-backing-services` first.

Do NOT attempt to run the corpus with services down. The corpus pipeline crashes loud on screening failures (by design — `ScenarioRunner.ok_or_raise`). This is correct behavior, not a bug.

---

## Step 2 — Correctness (10/10 rule coverage)

```bash
make test-corpus
```

This runs `mix corpus.validate --reset`, which:
1. Drops and recreates the `atomic_fi_corpus` Postgres schema
2. Loads all 10 catalog scenarios from `corpus/zen_rules/`
3. Inserts entities via production contexts (AccountHolderContext, etc.)
4. Creates transactions and diffs against `_expected` blocks
5. Prints a markdown report with match/mismatch/new counts per scenario

**What to check in the output:**
- All 10 scenarios run
- `mismatch = 0` (no correctness regressions)
- `setup_error = 0` (no entity creation failures)
- `engine_error = 0` (all rules evaluated successfully)

The 10 scenarios cover all 10 rules:

| Scenario slug | Rule triggered | Cite |
|---|---|---|
| `ofac_sdn_match` | ofac_sdn_match | 31 CFR §501.404 |
| `cip_kyc_gate` | cip_kyc_not_approved | BSA §326 |
| `ctr_structuring` | ctr_structuring | BSA §5324 |
| `smurfing_pattern_sar_eligible` | smurfing_pattern_sar_eligible | BSA §5324 |
| `prohibited_risk_freeze` | prohibited_risk_freeze | 31 CFR §1010.230 |
| `ah_country_kp_residence` | ah_country_kp_residence | OFAC E.O. 13466 |
| `business_ah_zero_bos` | business_ah_zero_bos | CTA; 31 CFR §1010.380 |
| `internal_blocklist_lastname` | internal_blocklist_lastname | FFIEC BSA/AML |
| `stableaml_wallet_blocklist` | stableaml_wallet_blocklist | 31 CFR §501.404 + GENIUS §4(a)(5) |
| `de_minimis_stablecoin` | stablecoin_block_unverified | 31 CFR §1020.220 |

---

## Step 3 — Scale (optional)

For large-scale throughput testing, use the bench target:

```bash
make bench BENCH_LEVELS=1,100,1000
```

Each VU level spawns N parallel virtual users, each running one of the 10 scenarios round-robin. At level 1000: ~100 copies of each scenario = ~5,000-10,000 transactions.

For higher scales, bump the DB pool:

```bash
POOL_SIZE=200 make bench BENCH_LEVELS=1,100,1000,2000
```

The bench writes a markdown report under `benchmarks/` with:
- Per-level throughput (txns/sec, p50/p95/p99 latency)
- Match/mismatch/error counts per level
- Environment fingerprint (CPU, Postgres, ZenRule version)

### Synthetic corpus at specific row count

To generate a specific number of synthetic transactions:

```bash
# StableAML: generate 1000 transactions + validate
mix corpus.generate.stableaml --emit-corpus --txns 1000 --seed 42
mix corpus.validate corpus/zen_rules/stableaml_wallet_blocklist --reset

# SAML-D: synthetic 10k rows → sharded corpus → validate
mix corpus.generate.saml_d --synthetic --rows 10000 --seed 42 --shards 1 --out tmp/corpus/saml-d-10k
mix corpus.validate tmp/corpus/saml-d-10k --reset

# AMLGentex: synthetic 10k rows
mix corpus.generate.amlgentex --synthetic --rows 10000 --seed 42 --shards 1 --out tmp/corpus/amlgentex-10k
mix corpus.validate tmp/corpus/amlgentex-10k --reset
```

Determinism: same `--seed` → byte-identical NDJSON every run (via `SyntheticSeed` module).

---

## Step 4 — Rollup

Read the validate/bench output and format a rollup. Use the format in `references/rollup-format.md`.

For `corpus.validate` output: count transactions per `rejected_rule` in the actual results.
For `corpus.bench` output: read the generated markdown report under `benchmarks/`.

---

## Step 5 — Probes

Standard probes (adapt based on actual rollup):

| # | Question |
|---|---|
| P1 | "Every BLOCKED transaction with its rejecting rule and regulation cite." |
| P2 | "Every counterparty scored ≥95 on Watchman with their SDN list source." |
| P3 | "Every account holder whose CIP is in progress and the transactions queued behind." |
| P4 | "Every transaction that hit two or more rules, with both cites." |
| P5 | "Daily blocked-transaction count over the seeded period, by scenario." |
| P6 | "Every internal-blocklist hit grouped by last name." |

See the full probe card at `example-apps/lotus-embed/probes/correctness.md`.

---

## Prerequisites

1. Backing services: `make run-backing-services` (Watchman :8084, ZenRule :8090)
2. Postgres: running and migrated
3. Catalog scenarios committed: `corpus/zen_rules/` (10 scenarios, checked in)

---

## Hard rules

- **Compose existing tools.** Use `make test-corpus`, `make bench`, `mix corpus.validate`, `mix corpus.generate.*`. Never generate NDJSON from scratch.
- **No graceful fallbacks.** Service down → preflight refuses to proceed. Entity creation failure → ScenarioRunner crashes (ok_or_raise).
- **No auto-commit.** DB state is in `atomic_fi_corpus` schema (droppable via `--reset`). Bench reports go to `benchmarks/` (gitignored until explicitly committed).
- **Real services required.** Watchman + ZenRule must be running.
- **Determinism.** Catalog scenarios are committed fixtures — same input every run. Synthetic generators use `SyntheticSeed` with `--seed` for reproducible output.
- **Lotus probes are manual.** This skill suggests questions; the officer runs them.

---

## Reference files

- **`references/rollup-format.md`** — per-rule summary and overall rollup output format

## Existing infrastructure (do not duplicate)

- `Makefile` targets: `test-corpus`, `bench`, `run-backing-services`, `reseed-*`
- `lib/mix/tasks/corpus.validate.ex` — correctness validation
- `lib/mix/tasks/corpus.bench.ex` — k6-style VU sweep
- `lib/mix/tasks/corpus.generate.stableaml.ex` — StableAML corpus generation
- `lib/mix/tasks/corpus.generate.saml_d.ex` — SAML-D corpus generation
- `lib/mix/tasks/corpus.generate.amlgentex.ex` — AMLGentex corpus generation
- `lib/atomic_fi/corpus/synthetic_seed.ex` — deterministic RNG generators
- `lib/atomic_fi/corpus/scenario_runner.ex` — insertion engine
- `corpus/zen_rules/` — 10 hand-curated catalog scenarios

## Related

- [corpus-from-rule](../corpus-from-rule/SKILL.md) — per-rule corpus generation
- [generate-rules](../generate-rules/SKILL.md) — multi-URL rule generation
- [guides/verifying_correctness.md](../../../guides/verifying_correctness.md) — the why and where
