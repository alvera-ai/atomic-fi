---
name: zenrule-author
description: Authors and verifies JDM (JSON Decision Model) rule files for the atomic-fi ZenRule engine from English-language requirements. Use whenever the user wants to write, edit, or test a compliance / payment-rules decision — including phrases like "add a rule", "create a ruleset", "write a KYC check", "block stablecoin", "de minimis", "limit transactions when X", "compliance gap", "GENIUS Act", "BSA §326", "OFAC screening rule", or any change that should land in `priv/zenrule/<rule_type>/`. The skill grounds itself in the real `AtomicFi.RuleEngine.Payload` schema, generates the JDM JSON directly under the correct rule-type subdirectory, builds test contexts from the rule's input columns, iteratively tests against the live ZenRule agent via curl, and amends the rule until all tests pass or escalates after a soft cap. Saved rules immediately surface in the JDM editor at `http://localhost:5173/rules/<rule_type>` after a browser refresh (the agent picks the file up within ~5s of the write).
---

# zenrule-author

Turn an English-language compliance/payment rule into a working JDM decision file under `priv/zenrule/<rule_type>/`, verified against the live agent and visible in the editor UI on the next refresh.

You are the author and the QA. The user provides intent; you handle JDM syntax, the schema lookup, test design, and the recursive curl loop.

## Rule-type layout (read first)

The rule corpus is split into **one ZenRule project per rule_type**, mirrored 1:1 on disk:

```
priv/zenrule/
├── onboarding/                 ← project key: "onboarding"
│   └── *.json
└── transaction-screening/      ← project key: "transaction-screening"
    └── *.json  (de_minimis.json lives here — prod rule)
```

Pick the subdir based on what the rule decides about:

- **onboarding** — about an entity (account holder, business, beneficial owner) and whether it may transact at all. Examples: KYC status gates, residency sanctions on the sender, beneficial-ownership floors, PEP-on-AH reviews. Use-cases #6–#10, #15, #27–#29, #45, #48, etc.
- **transaction-screening** — about a specific transaction and whether *this* movement may proceed. Examples: OFAC SDN bands on the counterparty, country corridors, structuring/velocity, stablecoin gates, travel-rule data, mixer recipients. Use-cases #11–#11e, #12–#14, #16–#22, #30–#34, #41–#43, #46–#47, #49–#57.

If the user's prompt doesn't make the subdir obvious, ask once.

The corresponding ZenRule project key is identical to the subdir name (`onboarding` or `transaction-screening`); the agent exposes:

```
POST /api/projects/<rule_type>/evaluate/<filename>.json
```

After the file is written, refresh `http://localhost:5173/rules/<rule_type>` in the browser; the new rule will appear in the list (the editor's Phoenix backend reads the same volume on each list call, no caching).

## When to use

Trigger whenever the user describes a payment-rule outcome they want. Examples:
- "Add a rule that blocks stablecoin transfers to un-KYC'd payees"
- "Write a de minimis variant for cross-border ACH"
- "Right now `de_minimis.json` doesn't check sanctions — close that"
- "What rule would close the gap from use-case #30?"

If they only ask a question ("does the current rule cover X?"), answer it without invoking the loop. The loop is for **authoring**.

---

## The end-to-end workflow

```
1. CAPTURE     →  Clarify the rule + rule_type in plain English (1-3 questions, no more)
2. GROUND      →  Read the schema reference + relevant existing rules
3. DRAFT       →  Generate the .json under priv/zenrule/<rule_type>/<name>.json
4. DESIGN      →  Build a test matrix from the rule's input columns; confirm with user
5. SMOKE-TEST  →  Announce → evaluate.sh each case → diff → amend → save → wait → re-run until green
6. HAND OFF    →  Append full matrix to test-inputs.md; surface a curated 2–3 case set for the user to paste into the editor's Simulator panel
```

Treat steps 1–4 as preparation. Step 5 is the recursive test loop with an explicit pre-announcement — that's the load-bearing part. Step 6 hands the rule off to the user with a small UI-checkable test set so they can independently verify in the browser.

---

## Step 1 — Capture intent

Read what the user said. If the rule + rule_type is unambiguous, skip the questions. Otherwise ask at most **three** focused questions before drafting. Good questions narrow:

- Which **rule_type** does this belong to: `onboarding` (about the entity) or `transaction-screening` (about a specific transaction)?
- Which input fields drive the decision? (e.g. `transaction_type`, payee `kyc_status`, an amount threshold)
- Should this **replace** an existing rule, **extend** it (add columns/rows), or be a **new** standalone file?
- What's the regulatory anchor — point me at the use-case in `guides/use-cases.md` if there is one. (Citations live in the rule's `_description` fields.)

Bad questions to avoid: "Tell me everything about your domain." Don't make the user redo work. The schema, the existing rules, and `guides/use-cases.md` are yours to read.

---

## Step 2 — Ground in the schema and prior art

Before writing JDM, load these in this order:

1. **`references/payload-schema.md`** — the shape of the context every rule receives. The rule's `field` expressions (e.g. `transaction.transaction_type`, `creditor_payment_account.account_holder.kyc_status`) must resolve in this tree.
2. **`priv/zenrule/<rule_type>/`** — list it. Read the file the user named, or the closest match in the same rule_type. Existing rules are templates; copy their node/edge structure and only change the decision-table content. If extending a transaction-screening rule, `priv/zenrule/transaction-screening/de_minimis.json` is the canonical reference.
3. **`guides/use-cases.md`** — only when the user cites a use-case number, or when the rule maps to a clear regulatory anchor (BSA §326, OFAC 31 CFR §501.404, GENIUS §4(a)(5), etc.). Cite the anchor in the `_description` of each rule row so the file documents itself.

If a field the user mentions isn't in the payload schema, **stop and tell the user** — don't invent it. The rule will silently match `null` at evaluation time and produce wrong results.

For JDM syntax questions (decision tables, hit policies, how to express `IN`/range/equality in a cell), see **`references/jdm-cheatsheet.md`**.

---

## Step 3 — Draft the rule file

**File destination**

- Default: `priv/zenrule/<rule_type>/<descriptive_name>.json`. Use snake_case, no spaces, `.json` extension.
- **Never overwrite `priv/zenrule/transaction-screening/de_minimis.json`** — that's the live production rule consumed by `AtomicFi.ZenRule.HttpClient.get_limits/1`. Any change ships to prod on the next 5s agent reload. If the user explicitly asks to edit prod, confirm verbally ("This will change prod behavior on next agent poll — proceed?") before writing.
- If extending an existing non-prod rule, save under a new name (e.g. `de_minimis_genius_v2.json`) rather than clobbering history.

**File shape** (canonical three-node graph: input → decision table → output)

```json
{
  "contentType": "application/vnd.gorules.decision",
  "nodes": [
    { "id": "request",    "type": "inputNode",         "name": "Request",  "position": { "x": 100, "y": 160 } },
    { "id": "<table_id>", "type": "decisionTableNode", "name": "<Title>",  "position": { "x": 380, "y": 160 }, "content": { ... } },
    { "id": "response",   "type": "outputNode",        "name": "Response", "position": { "x": 700, "y": 160 } }
  ],
  "edges": [
    { "id": "edge_request_table",  "type": "edge", "sourceId": "request",    "targetId": "<table_id>" },
    { "id": "edge_table_response", "type": "edge", "sourceId": "<table_id>", "targetId": "response" }
  ]
}
```

Build the decision-table `content` per the cheatsheet. Order rows from most-specific to most-general when `hitPolicy: "first"` — row order **is** the rule with that policy. The default row (catch-all, empty input cells) goes last.

**Save with `Write`, not by piping through bash** — `priv/zenrule/` is bind-mounted into the ZenRule container; once written, the agent picks it up on its next ~5s poll automatically. The JDM editor at `http://localhost:5173/rules/<rule_type>` will list the new file on the next browser refresh (its Phoenix backend lists the same volume).

---

## Step 4 — Design the test matrix

Generate scenarios mechanically from the rule's input columns. For a decision table with N rows:

- **N positive cases** — one per row, picking input values that should hit that row and only that row.
- **At least 1 negative / fallthrough case** — values that hit no specific row, exercising the default.
- **Boundary cases** — for any range or threshold input, a value just under and just over.

Each scenario is a `(name, context, expected_output)` triple. Context must conform to `references/payload-schema.md`. Expected output is the row's output cells — not a guess, the literal values from the table.

**Show the matrix to the user before running:**

```
I'll test these 5 scenarios:
  1. ach_pass         — credit_transfer + payee KYC approved   → ach_de_minimis
  2. stablecoin_pass  — internal_transfer + payee KYC approved → stablecoin_de_minimis
  3. stablecoin_block — internal_transfer + payee KYC pending  → stablecoin_kyc_required (zeros)
  4. boundary_amount  — amount = 2500 exactly                  → still allowed (≤ max_amount)
  5. fallthrough      — transaction_type "other"               → rule_default

Anything I should add or remove?
```

If the user adds scenarios, append them. Don't argue — they know their edge cases.

---

## Step 5 — Smoke tests (the recursive test loop)

This is the load-bearing step. Don't shortcut it.

**Before running anything, announce it to the user.** A single, short line — not a wall. Something like:

```
Drafted the rule at priv/zenrule/<rule_type>/<name>.json.
Running 7 smoke tests against the live agent now…
```

This matters because the smoke loop calls `evaluate.sh` repeatedly and the user sees the bash invocations stream past. Announcing the count up front frames the noise as deliberate verification, not random thrashing.

**Per iteration:**

1. **Save the rule** (or save once at iteration start if the previous iteration's amend already wrote).
2. **Wait ~6s** for the agent's filesystem provider poll. Don't poll faster — the agent's poll interval is 5s.
3. **Run each scenario** via `scripts/evaluate.sh <rule-type> <rule-name> <context-json-or-file>`. It returns the agent's full response (`result`, `trace`, `performance`).
4. **Diff actual vs expected** — compare the decision-table node's `output` (or `traceData.rule._id` if the user cares which row matched). Be exact: numeric `0` ≠ `null` ≠ `""`.
5. **For each mismatch, analyze before amending.** Read the trace's `traceData.reference_map` to see what inputs the agent actually consumed, and `traceData.rule` to see which row matched. Common root causes, in order of likelihood:
   - Cell expression syntax wrong (e.g. forgot quotes around a string literal — `"\"approved\""` not `"approved"`)
   - Row ordering issue with `hitPolicy: "first"` — a more general row catches first, the specific one is unreachable
   - Field path in `inputs[].field` doesn't resolve in the actual payload (typo, wrong nesting)
   - Expected output was wrong (rare but it happens — re-derive from the rule definition)
   - Rule saved to the wrong rule_type subdir → agent's `<other-project>/evaluate/<file>` 404s with "Loader error". The script's hint will say which entrypoints the agent currently sees.
6. **Amend, save, loop.**

**Soft cap: 5 iterations.** If you hit 5 and tests still fail, **stop and bring the user in** — per the systematic-debugging skill's Phase 4.5, three or more failed attempts is an architectural signal, not a code-fix signal. State plainly:
- Which tests still fail
- What you've already tried
- Your best guess at the root cause (rule structure issue, schema misunderstanding, wrong expected output, etc.)

Don't disguise a stuck loop as progress.

**What "green" means:** every scenario's actual output matches expected. Performance, trace, and result-shape are all fine to ignore — only `output` (or `traceData.rule._id` if rule-id matching was the assertion) must match.

---

## Step 6 — Hand off to the user

Once smoke tests are green:

1. **Tell the user smoke tests passed**, and give them a one-line summary: file path (including rule_type), smoke-scenario count, regulatory anchor if any, and the editor URL where the rule is now visible: `http://localhost:5173/rules/<rule_type>/<name>` (instruct them to refresh).

2. **Append the full matrix to `example-apps/atomic-fi-jdm-editor/example-rulesets/test-inputs.md`** under a new section for this ruleset. Use the existing format (scenario name, input JSON, expected output JSON, optional use-case anchor). Include the rule_type in the section heading so a future reader knows which subdir to look in.

3. **Surface a curated 2–3 case set the user can paste into the editor's Simulator panel** to independently verify the rule in the browser. Pick for maximum signal per paste:
   - Exactly **one PASS / happy-path** case
   - Exactly **one FAIL / BLOCK / non-happy** case (different result than the PASS case)
   - **Optionally one edge case** that exercises a guard or wildcard (e.g. a `null` field, a boundary value, a fall-through default)

   For each, give the user:
   - A short name and one-sentence description of what scenario it represents
   - The raw context JSON, formatted, ready to paste
   - The expected output (which field(s) to look at in the simulator result panel)

   This is **a subset** of the full smoke matrix from Step 4 — not a different test set. Pick the cases whose outputs are most distinguishable visually in the simulator's result tree, so the user can confirm correctness at a glance.

4. **Don't auto-commit.** Show the user what to commit; they decide the message and split.

---

## Hard rules

- **Never invent payload fields.** If a field isn't in `references/payload-schema.md` or the live `payload.ex`, refuse to use it.
- **Never overwrite `transaction-screening/de_minimis.json` without explicit confirmation.** It's the live prod rule.
- **Never write to the legacy `priv/zenrule/atomic-fi/` directory.** That subdir is from the pre-split layout and is not registered in the backend's `rule_types` config — files there are invisible to both the agent and the editor.
- **Never claim green based on the absence of an error.** Green requires every scenario's `output` to literally match expected.
- **Never silently change the input node's name from "Request"** — the simulator filters by node type, so the name is free-form, but downstream tooling and `test-inputs.md` examples assume "Request".

---

## Reference files

- **`references/payload-schema.md`** — fields available on `transaction`, `account_holder`, `debtor_payment_account`, `creditor_payment_account`, `debtor_counterparty`, `creditor_counterparty`. Read before drafting any `inputs[].field` expression.
- **`references/jdm-cheatsheet.md`** — JDM cell-expression syntax (equality, IN, range, null), hit policies, decision-table input/output schema. Read when writing or debugging table rows.
- **`scripts/evaluate.sh`** — `evaluate.sh <rule-type> <rule-name> '<context-json>'` (or a context-file path, or `-` for stdin). Prints the full agent response as JSON. Use this in the loop; don't roll your own curl invocations.

---

## Quick sanity checklist before invoking the loop

- [ ] Rule file written to `priv/zenrule/<rule_type>/`, NOT `priv/zenrule/atomic-fi/` (legacy) or `example-rulesets/` (docs)
- [ ] `<rule_type>` matches what the rule actually decides about (entity → `onboarding`, transaction → `transaction-screening`)
- [ ] `inputs[].field` paths verified against `references/payload-schema.md`
- [ ] String literals in cells are quoted (`"\"approved\""`, not `"approved"`)
- [ ] If `hitPolicy: "first"`: specific rows before catch-alls; default last
- [ ] Test matrix shown to the user and confirmed
- [ ] Agent is running (`docker compose -f local-dependencies.yaml ps zenrule` shows it up)
