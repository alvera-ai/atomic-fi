---
name: bruno-generate
description: Given a scenario slug, generates a Bruno .bru collection folder and CI-runs it with `bru run` to confirm all assertions pass. Use whenever the user wants to "generate Bruno tests for a scenario", "create .bru files for slug", "turn this corpus into a Bruno collection", or any phrasing that maps a corpus/zen_rules scenario to a runnable Bruno folder. One slug in, one green folder out. Never auto-commits.
---

# bruno-generate

Turn a single scenario slug into a runnable Bruno collection folder — `.bru` files with real HTTP requests and assertion blocks — verified green with `bru run`.

You are the author and the QA. The user names a scenario; you generate the `.bru` files, run them, iterate until green. **The human reviews and commits — never auto-commit.**

---

## Invocation

```
/bruno-generate --name <scenario-slug>
```

The slug must match an existing corpus folder under `corpus/zen_rules/<slug>/`. If the folder doesn't exist, stop — run `scenario-author` or `corpus-from-rule` first.

---

## Workflow

```
1. READ       →  Read corpus/zen_rules/<slug>/ (ndjson + proof.md)
2. PLAN       →  Map corpus to request sequence (see below)
3. GENERATE   →  Copy preludes from templates/, write .bru files
4. RUN        →  bru run <slug> --env local (or npx @usebruno/cli)
5. ITERATE    →  Fix failures. Re-run. Cap at 5 iterations.
6. HANDOFF    →  Surface file list + bru run result. DO NOT commit.
```

---

## Step 1 — Read the corpus

Read all four ndjson files and proof.md from `corpus/zen_rules/<slug>/`.

- `_expected` on each transaction row → assertion blocks
- `_label` → `docs {}` regulatory cite
- proof.md → narrative (simple PASS, BLOCK, or lifecycle BLOCK → action → PASS)

---

## Step 2 — Plan

Map ndjson to request sequence internally. Only pause for user confirmation if proof.md describes an ambiguous or unusual lifecycle flow.

1. `001-auth.bru` — copy from `templates/001-auth.bru` (bundled in this skill)
2. `002-warmup.bru` — copy from `templates/002-warmup.bru` (bundled in this skill)
3. Entity creates (AH → CP → PA, FK order)
4. Screening refresh steps if needed (see `references/bru-format.md` § Screening refresh)
5. Transactions (one `.bru` per row, assertions from `_expected`)
6. Lifecycle steps if proof.md shows BLOCK → action → PASS

### chain_screening decision

- Set `chain_screening: true` on any account holder whose legal entity needs Watchman screening (OFAC/sanctions scenarios). This triggers an async screening job at entity creation time.
- Set `chain_screening: false` for velocity/threshold rules (CIP, CTR, structuring, de minimis) where screening is irrelevant to the rule being tested.
- When in doubt, check whether the corpus `_expected` references an `ofac_*` or `sanctions_*` rule — if so, at least one party needs `chain_screening: true`.

---

## Step 3 — Generate

Folder name uses **kebab-case**: `ofac_sdn_match` → `ofac-sdn-match`.

Copy `templates/001-auth.bru` and `templates/002-warmup.bru` verbatim into the output folder. Do not modify them. Do not read other scenario folders to get these files.

For all other `.bru` files: each needs `meta {}`, `post/put {}`, `auth:bearer {}`, `headers {}`, `body:json {}`, `docs {}`, `assert {}`. Pre/post-response scripts for dynamic IDs.

See: `references/bru-format.md` for the full format spec — entity creation pattern, assertion syntax, ID chaining rules, screening refresh pattern. This is the authoritative format reference.

---

## Step 4 — Run

```sh
make run-backing-services
cd bruno/atomic-fi-scenarios && bru run <slug> --env local
```

If `local.bru` doesn't exist, copy from `environments/local.example.bru` and warn user to fill credentials.

---

## Step 5 — Iterate

On failure:
- **Assertion failure** — check API response shape, assertion syntax, or stale `_expected`
- **422** — payload shape wrong; compare against existing working `.bru` files
- **401** — auth step failed; check `local.bru` credentials
- **Undefined env var** — previous step didn't capture `res.body.id`; check post-response scripts

**Cap: 5 iterations.** If still failing, stop and bring the user in.

---

## Hard rules

- **One slug per invocation.**
- **Corpus must exist.** Stop if `corpus/zen_rules/<slug>/` is missing.
- **Copy prelude from templates/.** `001-auth.bru` and `002-warmup.bru` are bundled — copy them, don't read other scenarios.
- **Never auto-commit.**
- **Never skip assertion failures.**
- **Use server UUIDs in downstream requests.** Capture `res.body.id` in post-response scripts; don't use ndjson `external_id` values as FK references.
- **Kebab-case folder names.** Bruno folders use kebab-case even though corpus uses snake_case.

---

## Bundled files

- **`templates/001-auth.bru`** — standard auth prelude (copy verbatim)
- **`templates/002-warmup.bru`** — standard warmup prelude (copy verbatim)
- **`references/bru-format.md`** — .bru file format, naming, entity creation, assertion syntax, ID chaining, screening refresh

## Related

- [collection.bru](../../../bruno/atomic-fi-scenarios/collection.bru) — the parent collection docs
- [corpus-from-rule](../corpus-from-rule/SKILL.md) — generates the corpus this skill reads
- [scenario-author](../scenario-author/SKILL.md) — end-to-end vertical slice
