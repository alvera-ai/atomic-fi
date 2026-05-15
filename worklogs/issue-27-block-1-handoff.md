# atomic-fi · issue-27 · Block 1 — pick up handoff

You are taking over the `feat/issue-27-block-1-scenarios` branch. Two of
five P0 steps are committed (B.1 + B.2); B.4 + Steps A/C/D/E remain.
**Scope: only what's tracked in GitHub issue #27 — nothing else.**

## 1. Read first (in this order)

- `worklogs/p0-baseline-handover.md`            ← authoritative plan
- `worklogs/zenrule-velocity-limits.md`         ← rule-engine deep dive
- `guides/architecture.md`                      ← updated, includes C3
- `guides/core-modules.md`                      ← ERD + domain catalog
- `guides/capability-matrix.md`                 ← per-context status
- `CLAUDE.md` (project root) + `~/.claude/CLAUDE.md`

Branch state at handoff:
- Latest commits: B.1 (`75c049a` LA-tree + triggers + factory + tests),
  B.2 (`de68861` PA/CP lifecycle `ensure_linked_ledger_accounts`),
  doc refresh (`57fa710`, `73debfa` etc).
- `mix test` = **988 / 0**.
- Coveralls minimum still 90%; target ≥93% overall / ≥95% core (Step A).

## 2. House rules (non-negotiable)

- GPG-sign every commit (`-S`). Conventional commits. **No
  `Co-Authored-By` trailers.**
- `mix test --failed` to iterate; **never `--max-failures`**.
- Format + `mix credo --strict` before every commit.
- Test layer order: **context → controller → vitest → bruno**. Never
  jump.
- Controllers pass typed structs straight to context — no
  `Map.from_struct`, no `ExOpenApiUtils.Mapper.to_map` in controllers.
- Context functions wrapped in `def_with_rls_and_logging`; queries route
  through `AtomicFi.Repo` with `session:` so RLS is enforced.
- Agents propose, humans approve. Skills draft artifacts; the human
  driving the skill reviews and commits.

## 3. Approach — Spotify vertical slice

Get **one rule** working **end-to-end** before broadening. The reference
slice is the M1 ACH `de_minimis` velocity rule, already the canonical
ZenRule decision in `priv/static/zen_rules/`. Make every layer green for
that one rule before touching anything else. Then prove the skill-driven
path by adding a second rule **using the Claude Code skill stack** —
context → controller → vitest → bruno generated, reviewed, committed.

TDD throughout: write or update the failing test (or vitest spec, or
bruno assertion) FIRST, then make it pass. Never write production code
without a test that fails without it.

## 4. Step-by-step

### Slice 1 — de_minimis end-to-end (hand-written, TDD)

**B.4. Transaction flow rewrite**
- New `RuleEngine.Behaviour` signature returns
  `{:ok, %{applicable: %{la_id => [VelocityLimit]}, not_applicable: [la_id]}}`.
- `TransactionContext.create_transaction/2`:
   - load both sides as `ancestor_ids ++ [self] ++ descendant_ids`
   - pass two flat LA lists (`debit_las`, `credit_las`) to `RuleEngine.get_limits/3`
   - on the response, pick the leaf for each side by matching
     `la_type ∈ [:account_holder_payment_account_regime_root,
                  :counter_party_payment_account_regime_root]`
     AND `payment_account_id == side.pa.id`
   - call `LedgerEntryContext.create_entries/3` on the leaves
   - retire `:no_limits` as the default outcome; keep it only for genuine
     engine-decline cases (unknown regime, error envelope).
- Tests first:
   - `test/atomic_fi/rule_engine_test.exs` — pin the new shape
   - `test/atomic_fi/transaction_context_test.exs` — happy path
     (`status: :accepted`, balanced entries posted), rejected path
     (`status: :rejected` + `rejected_*` metadata), engine-decline path.
   - Update `RuleEngine.ZenRule` + its tests to match.
- Commit `feat(txn): {applicable, not_applicable} rule-engine contract,
  retire :no_limits default`.

**Step A. Coverage lift (only the modules B.4 touched)**
- Drive `/qa:increase-test-coverage` against `transaction_context.ex`,
  `rule_engine.ex`, `rule_engine/zen_rule.ex`, `ledger_entry_context.ex`.
  Target ≥95% per module.
- Once green, bump `coveralls.json` `minimum_coverage` 90 → 93 **in the
  same commit** as the last context's coverage commit.
- Commit `test(coverage): lift core modules to ≥95%, overall to ≥93%`.

**Step C. Layer 3 — vitest for the de_minimis slice**
```
make run-backing-services
make server &
cd integration-tests && pnpm state:create && pnpm test
```
- Cosmetic shape drift (renamed fields, response shape changes) → fix the
  vitest spec.
- Real semantic regression → fix `lib/` + add a new
  `mix test` case that pins it. Never let a green Layer 1 mask a Layer 3
  finding.
- Target 235 / 0 (1 skipped).
- Commit `test(vitest): refresh assertions post-rule-engine reshape`.

**Step D. Layer 4 — bruno for the de_minimis scenario**
```
cd bruno/atomic-fi-scenarios && bru run --env local
```
- Same triage rule as Step C: cosmetic → bruno asserts; semantic → `lib/`
  + new ExUnit case.
- Target 29 / 29 + 66 / 66.
- Commit `test(bruno): refresh scenarios post-rule-engine reshape`.

**Verification — Slice 1 done when:**
```bash
mix test                                              # 988+ / 0
mix coveralls                                         # ≥ 93% overall, ≥95% core
(cd integration-tests && pnpm test)                   # 235 / 0
(cd bruno/atomic-fi-scenarios && bru run --env local) # 29/29 + 66/66
```

### Slice 2 — second rule via skills (skill-driven, TDD)

Pick the next issue-27 scenario (consult the worklog — OFAC SDN
exact-match if Block 1 already covers ACH de_minimis). Then:

1. **New ZenRule rule** — drive the (planned) `zenrule-rules` skill or
   the human-equivalent today (Claude Code session to author the JDM
   draft). The draft is reviewed by the engineer (you), committed under
   `priv/static/zen_rules/<scenario>.json`.
2. **New Elixir context** if the scenario needs schema not already there
   — `/dev:create-rest-api` scaffolds schema + migration + context +
   controller + tests. TDD: read the generated test, run it, watch it
   fail (or pass), iterate.
3. **Controller test** (Layer 2 ConnCase) — `schema_assert` covers it.
4. **vitest spec** — `/usecase-vitest` skill authors the spec, records
   the API call sequence. Run it. Commit.
5. **Bruno collection addition** — `/vitest-to-bruno` agent reads the
   vitest spec + recordings, emits a runnable Bruno folder under
   `bruno/atomic-fi-scenarios/<scenario>/`, verifies via `bru run`.

Verification gate identical to Slice 1 (`mix test` + `mix coveralls` +
vitest + bruno all green).

### Step E. Close out

- Write `docs/architecture.md` mirroring `guides/architecture.md` for
  the Docusaurus site (C4 levels 1–3, ledger tree, the seam pattern).
  Source content already in `guides/architecture.md` + the four blocks
  in `worklogs/p0-baseline-handover.md §8`.
- Final commit `chore(p0): close baseline — coverage, txn flow, Layer
  3+4 green, second scenario via skills, arch.md`.
- `git push origin feat/issue-27-block-1-scenarios`.
- Open PR if not already open. Body summarises the two slices + the
  metrics table.

## 5. Scope discipline

If something pops up that is NOT in issue #27, log it in
`worklogs/issue-27-handover.md` under "Out of scope, defer" and keep
moving. Examples of things to NOT do right now:

- New REST endpoints unrelated to the two scenarios.
- Mass refactors of contexts outside the txn / rule-engine / ledger path.
- Mox seam expansion to new external services.
- LiveView anything (atomic-fi is API-only).
- Adding agent infrastructure (Lotus integration, internal-agent REST
  endpoints) — that's a separate epic.

## 6. Definition of done

- All four test layers green on both slices.
- Coveralls ≥ 93% overall / ≥ 95% on every module touched in Slice 1.
- `git status` clean, branch pushed, PR description lists the two
  slices.
- `docs/architecture.md` exists in the Docusaurus site path.

## 7. Format for your responses

Match the existing thread style — terse ASCII diagrams for explaining
schema/flow changes, 1–2 lines of prose, "Proceed?" to gate decisions.
Don't write paragraphs of explanation; show the change and ask.
