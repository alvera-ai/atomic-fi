---
name: zenrule-author
description: Authors and verifies JDM (JSON Decision Model) rule files for the atomic-fi ZenRule engine from English-language requirements. Use whenever the user wants to write, edit, or test a compliance / payment-rules decision — including phrases like "add a rule", "create a ruleset", "write a KYC check", "block stablecoin", "de minimis", "limit transactions when X", "compliance gap", "GENIUS Act", "BSA §326", "OFAC screening rule", or any change that should land in `priv/zenrule/atomic-fi/`. The skill grounds itself in the real `AtomicFi.RuleEngine.Payload` schema, generates the JDM JSON directly, builds test contexts from the rule's input columns, iteratively tests against the live ZenRule agent via curl, and amends the rule until all tests pass or escalates after a soft cap.
---

# zenrule-author

Turn an English-language compliance/payment rule into a working JDM decision file in `priv/zenrule/atomic-fi/`, verified against the live agent.

You are the author and the QA. The user provides intent; you handle JDM syntax, the schema lookup, test design, and the recursive curl loop.

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
1. CAPTURE   →  Clarify the rule in plain English (1-3 questions, no more)
2. GROUND    →  Read the schema reference + relevant existing rules
3. DRAFT     →  Generate the .json under priv/zenrule/atomic-fi/<name>.json
4. DESIGN    →  Build a test matrix from the rule's input columns; confirm with user
5. LOOP      →  evaluate.sh each case → diff actual vs expected → amend → save → wait → re-run
6. RECORD    →  Append the green scenarios to test-inputs.md; report to user
```

Treat steps 1–4 as preparation. Step 5 is the recursive test loop — that's the load-bearing part. Step 6 is so future-you (and the next session) can see what was verified.

---

## Step 1 — Capture intent

Read what the user said. If the rule is unambiguous, skip the questions. Otherwise ask at most **three** focused questions before drafting. Good questions narrow:

- Which input fields drive the decision? (e.g. `transaction_type`, payee `kyc_status`, an amount threshold)
- Should this **replace** an existing rule, **extend** it (add columns/rows), or be a **new** standalone file?
- What's the regulatory anchor — point me at the use-case in `guides/use-cases.md` if there is one. (Citations live in the rule's `_description` fields.)

Bad questions to avoid: "Tell me everything about your domain." Don't make the user redo work. The schema, the existing rules, and `guides/use-cases.md` are yours to read.

---

## Step 2 — Ground in the schema and prior art

Before writing JDM, load these in this order:

1. **`references/payload-schema.md`** — the shape of the context every rule receives. The rule's `field` expressions (e.g. `transaction.transaction_type`, `creditor_payment_account.account_holder.kyc_status`) must resolve in this tree.
2. **`priv/zenrule/atomic-fi/`** — list it. Read the file the user named, or the closest match. Existing rules are templates; copy their node/edge structure and only change the decision-table content.
3. **`guides/use-cases.md`** — only when the user cites a use-case number, or when the rule maps to a clear regulatory anchor (BSA §326, OFAC 31 CFR §501.404, GENIUS §4(a)(5), etc.). Cite the anchor in the `_description` of each rule row so the file documents itself.

If a field the user mentions isn't in the payload schema, **stop and tell the user** — don't invent it. The rule will silently match `null` at evaluation time and produce wrong results.

For JDM syntax questions (decision tables, hit policies, how to express `IN`/range/equality in a cell), see **`references/jdm-cheatsheet.md`**.

---

## Step 3 — Draft the rule file

**File destination**

- Default: `priv/zenrule/atomic-fi/<descriptive_name>.json`. Use snake_case, no spaces, `.json` extension.
- **Never overwrite `de_minimis.json`** — that's the live production rule (`AtomicFi.ZenRule.HttpClient.get_limits/1` hardcodes that filename, so any change ships to prod on the next 5s agent reload). If the user explicitly asks to edit prod, confirm verbally ("This will change prod behavior on next agent poll — proceed?") before writing.
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

**Save with `Write`, not by piping through bash** — `priv/zenrule/atomic-fi/` is bind-mounted into the ZenRule container; once written, the agent picks it up on its next 5s poll automatically.

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

## Step 5 — The recursive test loop

This is the load-bearing step. Don't shortcut it.

**Per iteration:**

1. **Save the rule** (or save once at iteration start if the previous iteration's amend already wrote).
2. **Wait ~5s** for the agent's filesystem provider poll. Don't poll faster — the agent's poll interval is 5s. Sleeping 6s is enough.
3. **Run each scenario** via `scripts/evaluate.sh <rule-name> <context-json-or-file>`. It returns the agent's full response (`result`, `trace`, `performance`).
4. **Diff actual vs expected** — compare the decision-table node's `output` (or `traceData.rule._id` if the user cares which row matched). Be exact: numeric `0` ≠ `null` ≠ `""`.
5. **For each mismatch, analyze before amending.** Read the trace's `traceData.reference_map` to see what inputs the agent actually consumed, and `traceData.rule` to see which row matched. Common root causes, in order of likelihood:
   - Cell expression syntax wrong (e.g. forgot quotes around a string literal — `"approved"` not `approved`)
   - Row ordering issue with `hitPolicy: "first"` — a more general row catches first, the specific one is unreachable
   - Field path in `inputs[].field` doesn't resolve in the actual payload (typo, wrong nesting)
   - Expected output was wrong (rare but it happens — re-derive from the rule definition)
6. **Amend, save, loop.**

**Soft cap: 5 iterations.** If you hit 5 and tests still fail, **stop and bring the user in** — per the systematic-debugging skill's Phase 4.5, three or more failed attempts is an architectural signal, not a code-fix signal. State plainly:
- Which tests still fail
- What you've already tried
- Your best guess at the root cause (rule structure issue, schema misunderstanding, wrong expected output, etc.)

Don't disguise a stuck loop as progress.

**What "green" means:** every scenario's actual output matches expected. Performance, trace, and result-shape are all fine to ignore — only `output` (or `traceData.rule._id` if rule-id matching was the assertion) must match.

---

## Step 6 — Record what shipped

Once green:

1. Append the scenarios to **`example-apps/atomic-fi-jdm-editor/example-rulesets/test-inputs.md`** under a new section for this ruleset. Use the existing format (scenario name, input JSON, expected output JSON, optional use-case anchor).
2. Print a one-line summary to the user: file path, scenario count, regulatory anchor if any.
3. **Don't auto-commit.** Show the user what to commit; they decide the message and split.

---

## Hard rules

- **Never invent payload fields.** If a field isn't in `references/payload-schema.md` or the live `payload.ex`, refuse to use it.
- **Never overwrite `de_minimis.json` without explicit confirmation.** It's the live prod rule.
- **Never claim green based on the absence of an error.** Green requires every scenario's `output` to literally match expected.
- **Never silently change the input node's name from "Request"** — the simulator filters by node type, so the name is free-form, but downstream tooling and `test-inputs.md` examples assume "Request".

---

## Reference files

- **`references/payload-schema.md`** — fields available on `transaction`, `account_holder`, `debtor_payment_account`, `creditor_payment_account`, `debtor_counterparty`, `creditor_counterparty`. Read before drafting any `inputs[].field` expression.
- **`references/jdm-cheatsheet.md`** — JDM cell-expression syntax (equality, IN, range, null), hit policies, decision-table input/output schema. Read when writing or debugging table rows.
- **`scripts/evaluate.sh`** — `evaluate.sh <rule-name> '<context-json>'` or `evaluate.sh <rule-name> path/to/context.json`. Prints the full agent response as JSON. Use this in the loop; don't roll your own curl invocations.

---

## Quick sanity checklist before invoking the loop

- [ ] Rule file written to `priv/zenrule/atomic-fi/`, not `example-rulesets/`
- [ ] `inputs[].field` paths verified against `references/payload-schema.md`
- [ ] String literals in cells are quoted (`"\"approved\""`, not `"approved"`)
- [ ] If `hitPolicy: "first"`: specific rows before catch-alls; default last
- [ ] Test matrix shown to the user and confirmed
- [ ] Agent is running (`docker compose -f local-dependencies.yaml ps zenrule` shows it up)
