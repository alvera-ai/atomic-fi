---
name: generate-rules
description: Turns a list of regulation URLs into per-rule proofs (JDM rule + NDJSON corpus + proof.md) and combines them into a single regulator-readable master.md. Use whenever the user wants to "prove these regulations", "generate rules from URLs", "build proofs for CFR/USC/PDF links", or any phrasing that maps multiple regulation sources to end-to-end deterministic proofs. Orchestrates scenario-author and corpus-from-rule per URL, then concatenates all proofs into benchmarks/correctness/master.md. Never auto-commits.
---

# generate-rules

Turn a list of regulation URLs into per-rule proofs — one vertical slice per URL — then combine all proofs into a single regulator-readable `benchmarks/correctness/master.md`.

You are the orchestrator. For each URL you delegate to `scenario-author`. Your job is sequencing, progress tracking, and the final concatenation. **The human reviews and commits — never auto-commit.**

---

## Invocation

```
/generate-rules --urls <comma-separated URLs>
/generate-rules --file <path to file with one URL per line>
```

URLs may be CFR/USC links, PDF links, HTML regulation pages, or local file paths.

---

## Workflow

```
1. PARSE       →  Extract URL list. Deduplicate. Print and confirm with user.
2. LOOP        →  For each URL, sequentially:
                   a. FETCH    — WebFetch for HTTP, Read for local
                   b. DERIVE   — /scenario-author --regulation <url-or-path>
                                 (produces rule + corpus + proof.md)
                   c. REPORT   — "✓ [N/M] <slug> — proof green" or surface failure
3. COMBINE     →  Concatenate all proof.md files into master.md
4. HANDOFF     →  Surface file list + suggested commit message. DO NOT commit.
```

Sequential — one URL at a time. If a URL's proof fails, surface it and let the user decide: fix/retry or skip.

---

## Step 2b — Delegation

Invoke `scenario-author` in `--regulation` mode. It handles:
1. Deriving slug and rule_type
2. Grounding against `references/payload-schema.md` and `payload.ex`
3. Drafting JDM rule + corpus
4. Proof loop (`mix corpus.validate`) + stability check

**Do not duplicate scenario-author's logic.** Delegate entirely.

---

## Step 3 — Combine

Concatenate proofs into `benchmarks/correctness/master.md`.

See: `references/master-md-format.md`

---

## Hard rules

- **Sequential URL processing.** Never parallelize — corpus collisions produce non-deterministic results.
- **Delegate to scenario-author.** This skill orchestrates; it does not draft rules or write corpus files.
- **Never auto-commit.**
- **Never skip a failed proof silently.**
- **Never edit proof.md files.** Master.md concatenates them verbatim.
- **No graceful fallbacks.** If a URL can't be fetched, fail loud.

---

## Reference files

- **`references/master-md-format.md`** — the master.md output structure

## Related

- [scenario-author](../scenario-author/SKILL.md) — authors the vertical slice per regulation
- [corpus-from-rule](../corpus-from-rule/SKILL.md) — generates corpus from an existing rule
- [guides/verifying_correctness.md](../../../guides/verifying_correctness.md) — the why and where
