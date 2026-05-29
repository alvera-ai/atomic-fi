---
name: master-suite
description: Runs all catalog scenarios through the corpus pipeline, prints per-rule coverage and overall rollup, and suggests Lotus probe questions. Use whenever the user wants to "run the master suite", "test all rules", "run 10k transactions", "verify correctness", or any phrasing that requests a full multi-rule correctness check. Composes existing make targets + mix tasks — never auto-commits.
---

# master-suite

Run all catalog scenarios through the corpus pipeline sequentially. Every transaction runs, every rule fires, every `_expected` is checked. Print per-rule coverage, overall rollup, and suggest Lotus probes.

This is a **correctness** tool, not a load test. No VUs, no parallelism, no bench harness.

---

## Invocation

```
/master-suite                    # run all catalog scenarios (default)
/master-suite --seed 42          # same thing, explicit seed for synthetic generators
```

---

## Workflow

```
1. PREFLIGHT   →  Check backing services (Watchman :8084, ZenRule :8090).
                   If down: tell user to run `make run-backing-services`.
                   Do NOT proceed — services are required.

2. CORRECTNESS →  make test-corpus
                   Runs `mix corpus.validate --reset` against all committed
                   catalog scenarios under corpus/zen_rules/.
                   Verifies rule coverage with _expected diffs.

3. ROLLUP      →  Read the validate output. Print:
                   - Per-rule summary (hits, verdicts, blocked counts, regulatory cite)
                   - Overall rollup (PASS/REVIEW/BLOCK/FREEZE, coverage X/N)
                   - Accuracy summary (match/mismatch/new/setup_error/engine_error)

4. PROBES      →  Suggest 5-6 Lotus probe questions based on what fired.

5. HANDOFF     →  Summary of what was run + how to interpret results.
```

---

## Step 1 — Preflight

Check service health before running anything:

```bash
curl -sf http://localhost:8084/ping && echo "Watchman: UP" || echo "Watchman: DOWN"
curl -sf http://localhost:8090/api/health && echo "ZenRule: UP" || echo "ZenRule: DOWN"
```

If either is DOWN, tell the user:
> Watchman/ZenRule is down. Run `make run-backing-services` first.

Do NOT attempt to run the corpus with services down. The corpus pipeline crashes loud on screening failures (by design — `ScenarioRunner.ok_or_raise`). This is correct behavior, not a bug.

---

## Step 2 — Correctness

```bash
make test-corpus
```

This runs `mix corpus.validate --reset`, which:
1. Drops and recreates the `atomic_fi_corpus` Postgres schema
2. Loads all catalog scenarios from `corpus/zen_rules/`
3. Inserts entities via production contexts (AccountHolderContext, etc.)
4. Creates transactions and diffs against `_expected` blocks
5. Prints a markdown report with match/mismatch/new counts per scenario

**What to check in the output:**
- All scenarios run
- `mismatch = 0` (no correctness regressions)
- `setup_error = 0` (no entity creation failures)
- `engine_error = 0` (all rules evaluated successfully)

The catalog scenarios and the rules they test:

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

New rules added via `generate-rules` or `scenario-author` appear automatically — `corpus.validate` discovers all folders under `corpus/zen_rules/`.

---

## Step 3 — Rollup

Read the validate output and format a rollup. Use the format in `references/rollup-format.md`.

Count transactions per `rejected_rule` in the actual results. Report:
- Per-rule block: hits, verdict mix, blocked count, regulatory cite
- Overall: PASS/REVIEW/BLOCK/FREEZE totals, coverage N/N rules
- Accuracy: match/mismatch/new/setup_error/engine_error

---

## Step 4 — Probes

Standard probes (adapt based on actual rollup):

| # | Question |
|---|---|
| P1 | "Every BLOCKED transaction with its rejecting rule and regulation cite." |
| P2 | "Every counterparty scored ≥95 on Watchman with their SDN list source." |
| P3 | "Every account holder whose CIP is in progress and the transactions queued behind." |
| P4 | "Every transaction that hit two or more rules, with both cites." |
| P5 | "Daily blocked-transaction count over the seeded period, by scenario." |
| P6 | "Every internal-blocklist hit grouped by last name." |

Also suggest SQL versions the officer can paste directly into Lotus (New → New Query):

```sql
-- P1: Blocked transactions by rule
SELECT t.rejected_rule, count(*) as blocked
FROM transactions t WHERE t.status = 'rejected'
GROUP BY t.rejected_rule ORDER BY blocked DESC

-- P3: Overall verdict split
SELECT t.status, count(*) as total
FROM transactions t GROUP BY t.status
```

See the full probe card at `example-apps/lotus-embed/probes/correctness.md`.

> **Note:** Lotus sees `atomic_fi_corpus` via `LotusRepo` search_path. Data persists after `corpus.validate --reset` runs — the officer queries it after this skill finishes.

---

## Prerequisites

1. Backing services: `make run-backing-services` (Watchman :8084, ZenRule :8090)
2. Postgres: running and migrated
3. Catalog scenarios committed: `corpus/zen_rules/` (discovered automatically)

---

## Hard rules

- **Compose existing tools.** Use `make test-corpus`, `mix corpus.validate`. Never generate NDJSON from scratch.
- **Sequential, not parallel.** This is correctness verification. Every transaction runs one at a time. No VUs, no concurrency flags, no bench harness.
- **No graceful fallbacks.** Service down → preflight refuses to proceed. Entity creation failure → ScenarioRunner crashes (ok_or_raise).
- **No auto-commit.** DB state is in `atomic_fi_corpus` schema (droppable via `--reset`).
- **Real services required.** Watchman + ZenRule must be running.
- **Lotus probes are manual.** This skill suggests questions and SQL; the officer runs them.

---

## Reference files

- **`references/rollup-format.md`** — per-rule summary and overall rollup output format
- **`references/entity-mix.md`** — entity distribution and band architecture

## Existing infrastructure (do not duplicate)

- `Makefile` targets: `test-corpus`, `run-backing-services`
- `lib/mix/tasks/corpus.validate.ex` — correctness validation
- `lib/atomic_fi/corpus/scenario_runner.ex` — insertion engine
- `corpus/zen_rules/` — hand-curated catalog scenarios

## Related

- [corpus-from-rule](../corpus-from-rule/SKILL.md) — per-rule corpus generation
- [generate-rules](../generate-rules/SKILL.md) — multi-URL rule generation
- [guides/verifying_correctness.md](../../../guides/verifying_correctness.md) — the why and where
