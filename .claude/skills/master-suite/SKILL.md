---
name: master-suite
description: Populates a single tenant's DB with a large mixed-rule master suite (100 AH / 1,000 CP / 10,000 Txn), runs all rules, prints a per-rule summary and overall rollup, and suggests 5-6 Lotus probe questions for manual CSV export. Use whenever the user wants to "run the master suite", "populate the DB at scale", "run 10k transactions", "seed for the compliance demo", or any phrasing that requests a large-scale multi-rule test run. Never auto-commits.
---

# master-suite

Populate a single tenant's DB with a large mixed-rule master suite, run all rules, print per-rule summaries and an overall rollup, and suggest Lotus probe questions the officer can run manually.

You generate the data, insert through production contexts, collect verdicts, and report. **No auto-commit — this skill mutates the DB, not the repo.**

---

## Invocation

```
/master-suite --seed <integer>
```

Default seed: `42`. Same seed → same entities → same verdicts.

---

## Workflow

```
1. DISCOVER    →  Read all rules from corpus/zen_rules/ and priv/zenrule/.
                   Build a catalog: slug, rule_type, expected verdicts, entity patterns.
2. GENERATE    →  Draft master corpus ndjson under tmp/corpus/<seed>/master/.
                   100 AH, 1k CP, 10k Txn. Deterministic from seed.
                   See: references/entity-mix.md
3. INSERT      →  Bulk-insert via ScenarioRunner infrastructure:
                   - inject_search_path_after_connect!()
                   - ensure_schema!(true)
                   - build_system_session()
                   - seed_blocklists!(session, [scenario])
                   - run_vu(session, scenario, verbose: false)
                   Print progress every 500 transactions.
4. COLLECT     →  Gather per-transaction verdicts from run_vu results.
5. ROLLUP      →  Compute per-rule summary + overall rollup. Print to console.
                   See: references/rollup-format.md
6. PROBES      →  Suggest 5-6 Lotus probe questions. Print to console.
7. HANDOFF     →  Summary of what was inserted + how to run Lotus probes.
```

---

## Step 1 — Discover

Read each `corpus/zen_rules/<slug>/transactions.ndjson` to understand:
- What entity patterns trigger each rule
- What `_expected` verdicts each rule produces
- What `_label` cites are referenced

Build a rule catalog to drive entity generation.

---

## Step 2 — Generate

Draft the master corpus. Design entities so every catalog rule fires, with cross-firing intentional.

See: `references/entity-mix.md` for the full entity band breakdown, count targets, and determinism rules.

---

## Step 3 — Insert

Use `AtomicFi.Corpus.ScenarioRunner` — the same engine `mix corpus.validate` and `mix corpus.bench` use. The generated ndjson is in the format `ScenarioRunner.load_scenario/1` expects.

Progress: print every 500 transactions (10k takes minutes).

---

## Step 6 — Probes

Standard probes (adapt based on actual rollup):

| # | Question |
|---|---|
| P1 | "Every BLOCKED transaction with its rejecting rule and regulation cite." |
| P2 | "Every counterparty scored ≥95 on Watchman with their SDN list source." |
| P3 | "Every account holder whose CIP is in progress and the transactions queued behind." |
| P4 | "Every transaction that hit two or more rules, with both cites." |
| P5 | "Daily blocked-transaction count over the seeded period, by scenario." |
| P6 | "Every internal-blocklist hit grouped by last name." |

Add rule-specific probes based on what actually fired. See the full probe card at `example-apps/lotus-embed/probes/correctness.md`.

---

## Prerequisites

1. Backing services: `make run-backing-services` (Watchman :8084, ZenRule :8090)
2. Phoenix running: `mix phx.server`
3. BlocklistCache: warmed by `ScenarioRunner.seed_blocklists!` in Step 3

---

## Hard rules

- **Single tenant.** All data in one tenant via `ScenarioRunner.build_system_session()`.
- **Production contexts only.** Insert via `AccountHolderContext`, `CounterpartyContext`, etc. Never raw SQL.
- **Deterministic from seed.** No `DateTime.utc_now()` in entity generation.
- **No graceful fallbacks.** Entity creation failure → crash. Unexpected verdict → report as mismatch.
- **No auto-commit.** Ndjson under `tmp/` is gitignored. DB state is in `atomic_fi_corpus` schema (droppable via `--reset`).
- **Real services required.** Watchman + ZenRule must be running.
- **Lotus probes are manual.** This skill suggests questions; the officer runs them.

---

## Reference files

- **`references/entity-mix.md`** — entity band breakdown, count targets, determinism, ndjson output format
- **`references/rollup-format.md`** — per-rule summary and overall rollup output format

## Related

- [corpus-from-rule](../corpus-from-rule/SKILL.md) — per-rule corpus generation
- [generate-rules](../generate-rules/SKILL.md) — multi-URL rule generation
- [guides/verifying_correctness.md](../../../guides/verifying_correctness.md) — the why and where
- `lib/atomic_fi/corpus/scenario_runner.ex` — the insertion engine
- `lib/atomic_fi/corpus/synthetic_seed.ex` — deterministic RNG patterns
