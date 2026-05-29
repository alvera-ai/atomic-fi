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
2. STUDY      →  Read 2+ existing Bruno scenarios to learn conventions
                  See: references/bru-format.md
3. PLAN       →  Map corpus to request sequence: auth → warmup → entities → txns
                  → lifecycle steps. Print plan, confirm with user.
4. GENERATE   →  Write .bru files under bruno/atomic-fi-scenarios/<slug>/
5. RUN        →  bru run <slug> --env local (or npx @usebruno/cli)
6. ITERATE    →  Fix failures. Re-run. Cap at 5 iterations.
7. HANDOFF    →  Surface file list + bru run result. DO NOT commit.
```

---

## Step 1 — Read the corpus

Read all four ndjson files and proof.md from `corpus/zen_rules/<slug>/`.

- `_expected` on each transaction row → assertion blocks
- `_label` → `docs {}` regulatory cite
- proof.md → narrative (simple PASS, BLOCK, or lifecycle BLOCK → action → PASS)

---

## Step 3 — Plan

Map ndjson to request sequence:

1. `001-auth.bru` — standard prelude (copy verbatim)
2. `002-warmup.bru` — standard prelude (copy verbatim)
3. Entity creates (AH → CP → PA, FK order)
4. Transactions (one `.bru` per row, assertions from `_expected`)
5. Lifecycle steps if proof.md shows BLOCK → action → PASS

---

## Step 4 — Generate

Folder name uses **kebab-case**: `ofac_sdn_match` → `ofac-sdn-match`.

Each `.bru` file needs: `meta {}`, `post/put {}`, `auth:bearer {}`, `headers {}`, `body:json {}`, `docs {}`, `assert {}`. Pre/post-response scripts for dynamic IDs.

See: `references/bru-format.md` for the full format spec, entity creation pattern, assertion syntax, and ID chaining rules.

---

## Step 5 — Run

```sh
make run-backing-services
cd bruno/atomic-fi-scenarios && bru run <slug> --env local
```

If `local.bru` doesn't exist, copy from `environments/local.example.bru` and warn user to fill credentials.

---

## Step 6 — Iterate

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
- **Copy prelude verbatim.** `001-auth.bru` and `002-warmup.bru` are identical across scenarios.
- **Never auto-commit.**
- **Never skip assertion failures.**
- **Use server UUIDs in downstream requests.** Capture `res.body.id` in post-response scripts; don't use ndjson `external_id` values as FK references.
- **Kebab-case folder names.** Bruno folders use kebab-case even though corpus uses snake_case.

---

## Reference files

- **`references/bru-format.md`** — .bru file format, naming, entity creation pattern, assertion syntax, ID chaining

## Related

- [collection.bru](../../../bruno/atomic-fi-scenarios/collection.bru) — the parent collection docs
- [corpus-from-rule](../corpus-from-rule/SKILL.md) — generates the corpus this skill reads
- [scenario-author](../scenario-author/SKILL.md) — end-to-end vertical slice
