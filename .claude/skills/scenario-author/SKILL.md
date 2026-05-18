---
name: scenario-author
description: Authors a complete vertical slice (JDM rule + NDJSON corpus + proof.md) for a single use-cases.md row OR a regulation snippet (PDF/text) — for the atomic-fi ZenRule engine and corpus.validate write path. Use whenever the user wants to "add a scenario", "ship use-case #N", "build a rule + corpus for X", "close compliance gap Y", or any phrasing that maps one regulatory requirement to one end-to-end deterministic proof. Writes the rule AND the corpus AND iterates the proof loop in one transactional sweep. Saves under `priv/zenrule/<rule_type>/<slug>.json` and `corpus/zen_rules/<slug>/{account_holders,counterparties,payment_accounts,transactions}.ndjson` + `proof.md`. Never auto-commits — the human reviews and commits.
---

# scenario-author

Turn ONE row of `guides/use-cases.md` (or ONE regulation snippet) into a vertical slice that proves the platform implements that requirement:

```
   ┌────────────────────┐   ┌────────────────────┐   ┌──────────────────┐
   │  JDM rule          │   │  corpus ndjson     │   │  proof.md        │
   │  (what fires)      │ + │  (what was tested) │ → │  (what happened) │
   └────────────────────┘   └────────────────────┘   └──────────────────┘
                  ▲                                             ▲
                  └──────── byte-stable across reruns ──────────┘
```

You are the author **and** the QA. The user names a target (`row 10`, or `--regulation path/to.pdf`); you produce the slice, run the proof loop, and stop when the proof is green and byte-stable at concurrency 1 AND 8. **The human reviews and commits — never auto-commit.**

---

## Invocation modes

```
   /scenario:author <row-number>
       e.g.  /scenario:author 10        → reads row 10 of guides/use-cases.md

   /scenario:author --regulation <path>
       e.g.  /scenario:author --regulation docs/regs/genius-act-§4.pdf
                                          → reads the snippet and derives row-shape
```

Only one mode per invocation. If the user provides both, prefer `<row-number>` and ignore `--regulation`.

---

## The end-to-end workflow

```
  1. CAPTURE    →  Read the row OR snippet. Confirm rule_type and slug with the user (1 question max).
  2. GROUND     →  Lockstep-check references/payload-schema.md vs payload.ex. STOP if drift.
  3. DRAFT-RULE →  Write priv/zenrule/<rule_type>/<slug>.json (canonical 3-node graph).
  4. DRAFT-CORPUS →  Write corpus/zen_rules/<slug>/{AH,CP,PA,txn}.ndjson with inline _expected blocks.
  5. PROOF-LOOP →  mix corpus.validate corpus/zen_rules/<slug> --reset
                     --out corpus/zen_rules/<slug>/proof.md
                   Iterate (rule edits, corpus edits) until match-counts saturated.
  6. STABILITY  →  Re-run with --concurrency 1 and --concurrency 8; diff proofs;
                   if any diff, FAIL LOUD (do not silently regenerate).
  7. HANDOFF    →  Surface the file list to the user with the suggested commit message.
                   DO NOT commit. The human commits (GPG-signed, conventional, no Co-Authored-By).
```

Steps 1–4 are preparation. Steps 5–6 are the load-bearing proof loop — that's what differentiates this skill from a JDM scratchpad.

---

## Step 1 — Capture

If the user passed `<row-number>`:

1. Read the row from `guides/use-cases.md` (table row format: `| # | Scenario | Result | Regulations | Test |`).
2. Derive the **slug** (snake_case, descriptive, deterministic — e.g. row 10 → `prohibited_risk_freeze`). The slug is the corpus directory name AND the JDM filename stem AND the eval-harness golden directory name. Choose ONCE.
3. Decide `rule_type`:
   - **`onboarding`** — about an entity (AH, business, BO) and whether it may transact at all
   - **`transaction-screening`** — about a specific transaction and whether *this* movement may proceed
   - If ambiguous, **ask once**: "Onboarding or transaction-screening?"

If the user passed `--regulation <path>`:

1. Read the snippet (PDF via `Read` tool, or text file).
2. See `references/regulation-snippet-format.md` for the extraction template: regulatory cite → atomic predicate → verdict → schema needs.
3. Ask the user to confirm the derived `(slug, rule_type, verdict)` before drafting.

**Do not skip the capture step.** A wrong slug poisons the eval harness; a wrong rule_type 404s the agent.

See: `references/use-cases-row-format.md`

---

## Step 2 — Ground (lockstep guard)

**Non-negotiable.** Before drafting ANY JDM:

1. Open `references/payload-schema.md` (the schema doc this skill reads).
2. Open `lib/atomic_fi/rule_engine/payload.ex` (the live source of truth).
3. Diff: every field the rule will reference MUST appear in BOTH.
   - In `payload.ex` but missing from doc → **update doc first**, then draft.
   - In neither → **STOP**. Extend `payload.ex` with a failing test in `test/atomic_fi/rule_engine/payload_test.exs` BEFORE returning to this skill. The rule cannot move ahead of the payload.
4. If the field exists in payload but ISN'T POPULATED in `Payload.from_transaction/1` due to missing preloads → STOP and fix the preloads in `TransactionContext` (or the relevant context). The rule will silently see `null` otherwise.

This is the load-bearing invariant of this entire system; **do not bypass it under any condition.**

---

## Step 3 — Draft the rule

**File destination:** `priv/zenrule/<rule_type>/<slug>.json`. Snake_case, `.json`, **never** in `priv/zenrule/atomic-fi/` (legacy).

**Shape** (canonical three-node graph):

```json
{
  "contentType": "application/vnd.gorules.decision",
  "nodes": [
    { "id": "request",   "type": "inputNode",         "name": "Request",  "position": { "x": 100, "y": 160 } },
    { "id": "decide",    "type": "decisionTableNode", "name": "<Title>",  "position": { "x": 380, "y": 160 }, "content": { /* table or expression */ } },
    { "id": "response",  "type": "outputNode",        "name": "Response", "position": { "x": 700, "y": 160 } }
  ],
  "edges": [
    { "id": "edge_request_decide",  "type": "edge", "sourceId": "request", "targetId": "decide" },
    { "id": "edge_decide_response", "type": "edge", "sourceId": "decide",  "targetId": "response" }
  ]
}
```

- Use `decisionTableNode` when the decision is a small fixed table (≤ ~10 rows).
- Use `expressionNode` when the decision is a single conditional expression (faster to evaluate; harder for non-engineers to read in the editor).
- See `references/jdm-cheatsheet.md` for cell syntax (string-literal quoting, `IN`, ranges, `null` checks).
- Row ordering with `hitPolicy: "first"`: specific rows first, catch-all default last.
- Cite the regulatory anchor in each row's `_description`. The file is self-documenting.

**Never overwrite a production rule without explicit confirmation.** Production rules under `priv/zenrule/transaction-screening/` are consumed by `AtomicFi.ZenRule.HttpClient` on the next 5s agent poll. If the user asks to edit a prod rule, confirm: "This will change prod behavior on next agent poll — proceed?"

---

## Step 4 — Draft the corpus

**Folder destination:** `corpus/zen_rules/<slug>/`. Four files, one row per line:

```
   account_holders.ndjson    AccountHolderRequest-shaped; external_id is the stable handle
   counterparties.ndjson     CounterpartyRequest; refs parent via account_holder_external_id
   payment_accounts.ndjson   PaymentAccountRequest; refs parent via account_holder_external_id
                                                              OR counterparty_external_id
   transactions.ndjson       TransactionRequest with inline _label + _expected blocks
```

`<slug>` is the SAME slug from Step 1 — the JDM filename stem matches the corpus directory exactly. (The eval harness depends on this.)

**Row design:**

- One transaction row per decision-table band (positive case), plus at least one fall-through.
- Each AH/CP/PA row: set `external_id` to a unique handle prefixed with the slug (`pr-` for `prohibited_risk_freeze`, `mx-` for `ofac_mixer_usdc`, …). Unique prefixes prevent corpus collisions on shared schemas.
- Required scalars (else the contexts crash, which is correct):
  - `account_holders.ndjson`: `external_id`, `holder_type`, `status: "pending"`, `kyc_status`, `risk_level`, `enabled_currencies`, `legal_entity: { … }`
  - `payment_accounts.ndjson`: `external_id`, `account_holder_external_id` OR `counterparty_external_id`, `account_type`, `currency`
  - `transactions.ndjson`: `external_id`, `transaction_type`, `amount`, `currency`, `account_holder_external_id`, `debtor_external_id`, `creditor_external_id`
- Inline `_label`: `{regime, cite, scenario}` — the row's regulatory anchor in plain text.
- Inline `_expected`: the literal `%Transaction{}` fields to assert after the rule fires — `status`, `rejected_rule`, `rejected_period`, `rejected_direction`, `rejected_code`. **No graceful fallbacks** — if the expected verdict is `accepted`, write `"status": "accepted"` exactly, not `null` or omitted.

See: `references/output-contract.md`

---

## Step 5 — Proof loop

Bring backing services up:

```
   make run-backing-services
```

Run:

```
   mix corpus.validate corpus/zen_rules/<slug> --reset \
       --out corpus/zen_rules/<slug>/proof.md
```

Read the markdown report. Per-row outcomes:

- `match`     — `_expected` matches actual `%Transaction{}` state ✅
- `new`       — no `_expected` on the row; actual captured. **Fix this before the loop ends** — every row in this skill's output must declare an expectation.
- `mismatch`  — diff shown. Either the rule is wrong (edit JDM) or the corpus is wrong (edit ndjson). Decide deliberately, don't paper over.
- `setup_error`  — context rejected the payload (Ecto changeset error). Fix the ndjson row.
- `engine_error` — rule engine reachability or shape problem. Check agent is up (`docker compose ps zenrule`) and the rule file is loaded (`curl http://localhost:8090/api/projects/<rule_type>/entrypoints | jq`).

**Iteration cap: 5 rounds.** If you're still red at round 5, **stop and bring the user in** — three+ failed attempts is an architectural signal, not a code-fix signal. State plainly:
- Which rows still mismatch
- What you've tried
- Best-guess root cause (rule structure, schema misunderstanding, expected verdict wrong)

**For Watchman-unreachable scenarios** (row 53 pattern): the `ScreeningEngine.Behaviour` mock seam returns `{:error, :unreachable}`; the rule emits a REVIEW Control (NOT a BLOCK); the `audit_events` row is written by `ScreeningEngine.Default`'s error path (NOT by the rule). Facts vs decision separation — never put the audit write in the rule.

---

## Step 6 — Stability check

Once `mismatch == 0` at default concurrency:

```
   # Single-VU baseline
   mix corpus.validate corpus/zen_rules/<slug> --reset --concurrency 1 \
       --out corpus/zen_rules/<slug>/proof.md

   # Fan out, write to /tmp
   mix corpus.validate corpus/zen_rules/<slug> --reset --concurrency 8 \
       --out /tmp/<slug>.proof.md

   # Compare
   diff corpus/zen_rules/<slug>/proof.md /tmp/<slug>.proof.md
```

**Empty diff is required.** A byte-stable proof across concurrency is the regulator-walkable artifact this skill exists to produce. If the diff is non-empty, FAIL LOUD — investigate non-determinism (timestamps, rule engine non-determinism, races in preloads) before regenerating. **Never silently rewrite the proof to mask drift.**

---

## Step 7 — Handoff

Surface to the user:

```
   slice ready for review:
     priv/zenrule/<rule_type>/<slug>.json
     corpus/zen_rules/<slug>/account_holders.ndjson
     corpus/zen_rules/<slug>/counterparties.ndjson
     corpus/zen_rules/<slug>/payment_accounts.ndjson
     corpus/zen_rules/<slug>/transactions.ndjson
     corpus/zen_rules/<slug>/proof.md

   proof: match=<N>, mismatch=0, byte-stable @ concurrency 1 ↔ 8

   suggested commit message:
     feat(rules): add <slug> rule + corpus + proof
       row #<NN> of guides/use-cases.md
       regulatory anchor: <citation>
```

**Do not commit.** The human reviews and stages. Per house rules:
- GPG-signed (`git commit -S`)
- Conventional commit
- **No Co-Authored-By trailers**

If the slice is one of the 10 golden scenarios, also remind the user to:
1. Promote into `.claude/skills/scenario-author/evals/golden/<slug>/`
2. Add the row to `evals/cases.csv`
3. Populate the Test column in `guides/use-cases.md` (ExUnit + Bruno links)

---

## Hard rules

- **Lockstep first.** No drafting until `references/payload-schema.md` matches `payload.ex`.
- **Never invent payload fields.** If the rule needs a field that doesn't exist, STOP and extend the payload (with a failing test) before drafting.
- **Never auto-commit.** This skill writes; the human commits.
- **Never silently regenerate a non-byte-stable proof.** If concurrency 1 ↔ 8 diff, investigate.
- **Never put aggregators or verdict folds in the screening layer.** ScreeningEngine = facts, RuleEngine = decision.
- **No graceful fallbacks.** Missing invariant must fail loud (`get!`, `fetch!`, raise — never default + nil).
- **Never delete a loud-failure assertion when retargeting a scenario.** Re-target the scenario, keep the sentinel.
- **Slug must be identical** across `priv/zenrule/<rule_type>/<slug>.json`, `corpus/zen_rules/<slug>/`, and `evals/golden/<slug>/`. Pick once in Step 1.
- **Never write to `priv/zenrule/atomic-fi/`** (legacy; invisible to both the agent and the editor).

---

## Reference files

- **`references/payload-schema.md`** — the `AtomicFi.RuleEngine.Payload` shape. The rule may only reference paths documented here. Lockstep-checked against `payload.ex` on every invocation.
- **`references/use-cases-row-format.md`** — how to read a row of `guides/use-cases.md` and extract slug + rule_type + verdict + schema needs.
- **`references/regulation-snippet-format.md`** — how to extract the same fields from a regulatory PDF/text snippet (the `--regulation` mode).
- **`references/output-contract.md`** — the exact shape the skill must emit (JDM 3-node graph, four ndjson files, proof.md).
- **`references/jdm-cheatsheet.md`** — JDM cell-expression syntax (equality, IN, range, null checks), hit policies.
- **`scripts/evaluate.sh`** — smoke-test a single context against the live agent without going through the corpus validator. Use for fast iteration on a single decision-table row before running `mix corpus.validate`.
