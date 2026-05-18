# Output contract — the vertical slice this skill must emit

Every successful invocation of `/scenario:author` produces **exactly** these six files. Nothing more, nothing less.

```
   priv/zenrule/<rule_type>/<slug>.json                       ← JDM rule
   corpus/zen_rules/<slug>/account_holders.ndjson             ← entity graph (parents)
   corpus/zen_rules/<slug>/counterparties.ndjson              ← entity graph (parents)
   corpus/zen_rules/<slug>/payment_accounts.ndjson            ← entity graph (children)
   corpus/zen_rules/<slug>/transactions.ndjson                ← what fires the rule
   corpus/zen_rules/<slug>/proof.md                           ← what happened (byte-stable)
```

If any of the six is missing, the slice is **incomplete** — do not hand off.

The slug appears in three places and must match exactly:
- `priv/zenrule/<rule_type>/<slug>.json`
- `corpus/zen_rules/<slug>/`
- (later, when promoted) `.claude/skills/scenario-author/evals/golden/<slug>/`

**Golden snapshot layout** (when the slice gets promoted into the eval harness):

```
   .claude/skills/scenario-author/evals/golden/<slug>/
     rule.json                          ← the JDM (flat name; live rule_type recorded in .meta.json)
     account_holders.ndjson
     counterparties.ndjson
     payment_accounts.ndjson
     transactions.ndjson
     proof.md
     .meta.json                          { "row_number": NN, "rule_type": "...",
                                           "live_rule_path":   "priv/zenrule/.../X.json",
                                           "live_corpus_path": "corpus/zen_rules/Y/" }
     .human_edits_needed                 optional sidecar — flips the regression gate
```

The flat layout decouples the eval harness from production filename drift (seed rules predate the slug convention) while still recording the live paths for traceability via `.meta.json`.

---

## File 1 — `priv/zenrule/<rule_type>/<slug>.json`

Canonical three-node graph. See `references/jdm-cheatsheet.md` for cell syntax.

```json
{
  "contentType": "application/vnd.gorules.decision",
  "nodes": [
    { "id": "request",  "type": "inputNode",          "name": "Request",  "position": {"x":100,"y":160} },
    { "id": "decide",   "type": "decisionTableNode",  "name": "<Title>",  "position": {"x":380,"y":160}, "content": { /* rows */ } },
    { "id": "response", "type": "outputNode",         "name": "Response", "position": {"x":700,"y":160} }
  ],
  "edges": [
    { "id": "edge_request_decide",  "type": "edge", "sourceId": "request", "targetId": "decide" },
    { "id": "edge_decide_response", "type": "edge", "sourceId": "decide",  "targetId": "response" }
  ]
}
```

Hard rules:
- `inputNode.name` MUST be `"Request"` (downstream tooling assumes this).
- Every row in the decision table needs a `_description` citing the regulatory anchor.
- With `hitPolicy: "first"`: specific rows BEFORE catch-all default.
- String literals in cells must be quoted: `"\"approved\""`, not `"approved"`.

---

## Files 2–5 — corpus ndjson

One JSON object per line. No leading/trailing whitespace per line. **One terminal newline** at end of file.

### `account_holders.ndjson`

```jsonl
{"external_id":"<slug-ah-handle>","holder_type":"individual","status":"pending","kyc_status":"approved","risk_level":"low","enabled_currencies":["USD"],"legal_entity":{"legal_entity_type":"individual","first_name":"Alice","last_name":"Sender"}}
```

Required keys (else context crashes — which is correct):
- `external_id` (stable handle, unique across all corpora)
- `holder_type`
- `status: "pending"` (default state on insert)
- `kyc_status`
- `risk_level`
- `enabled_currencies`
- `legal_entity` (nested object)

### `counterparties.ndjson`

```jsonl
{"external_id":"<slug-cp-handle>","account_holder_external_id":"<slug-ah-handle>","counterparty_type":"individual","legal_entity":{"legal_entity_type":"individual","first_name":"Bob","last_name":"Recipient"}}
```

Reference parent AH via `account_holder_external_id`.

### `payment_accounts.ndjson`

```jsonl
{"external_id":"<slug-pa-debtor>","account_holder_external_id":"<slug-ah-handle>","account_type":"wallet","currency":"USD"}
{"external_id":"<slug-pa-creditor>","counterparty_external_id":"<slug-cp-handle>","account_type":"wallet","currency":"USD"}
```

Each row references EITHER `account_holder_external_id` OR `counterparty_external_id` — never both, never neither.

### `transactions.ndjson`

```jsonl
{"external_id":"<slug-txn-01>","transaction_type":"credit_transfer","amount":4000,"currency":"USD","account_holder_external_id":"<slug-ah-handle>","debtor_external_id":"<slug-pa-debtor>","creditor_external_id":"<slug-pa-creditor>","_label":{"regime":"<regime>","cite":"<citation>","scenario":"<one-sentence intent>"},"_expected":{"status":"accepted","rejected_rule":null}}
```

Required scalars:
- `external_id`
- `transaction_type`
- `amount` (minor units — integer cents)
- `currency`
- `account_holder_external_id`
- `debtor_external_id`
- `creditor_external_id`

Required reflective blocks:
- `_label`: `{regime, cite, scenario}` — what this row tests, in plain English
- `_expected`: the literal `%Transaction{}` post-state — the assertion the corpus validator runs

`_expected` shape (write only the fields the rule actually decides on; **no graceful fallbacks** — write the value or omit the key, never `null` as a "don't care"):

```json
{
  "status": "accepted",
  "rejected_rule": null,
  "rejected_period": null,
  "rejected_direction": null,
  "rejected_code": null
}
```

For `rejected` rows, the strings must match the JDM band identifier exactly:

```json
{
  "status": "rejected",
  "rejected_rule": "prohibited_risk_freeze",
  "rejected_period": "daily",
  "rejected_direction": "debit",
  "rejected_code": "prohibited_risk_freeze"
}
```

---

## File 6 — `corpus/zen_rules/<slug>/proof.md`

The byte-stable artifact emitted by `mix corpus.validate --reset --out`. **The skill never writes this file by hand** — the mix task writes it.

Acceptance:

```
   # Single-VU baseline
   mix corpus.validate corpus/zen_rules/<slug> --reset --concurrency 1 \
       --out corpus/zen_rules/<slug>/proof.md

   # Stability check
   mix corpus.validate corpus/zen_rules/<slug> --reset --concurrency 8 \
       --out /tmp/<slug>.proof.md
   diff corpus/zen_rules/<slug>/proof.md /tmp/<slug>.proof.md
   # → empty diff
```

The committed `proof.md` is the one written at `--concurrency 1`. The skill's job ends when the diff is empty.

---

## Handle naming convention

Prefix every `external_id` with a 2–4-character slug initialism so reruns of multiple corpora on the same schema don't collide:

```
   slug                              prefix
   ───────────────────────────       ──────
   prohibited_risk_freeze            pr-
   cip_kyc_in_progress               kyc-
   ofac_sdn_high_score               sdn-
   ah_country_kp_residence           kp-
   ctr_sub_threshold_structuring     ctr-
   business_ah_zero_bos              bo-
   ofac_mixer_usdc                   mx-
   internal_blocklist_lastname       bl-
   watchman_unreachable_held         wm-
   de_minimis_ach                    dm-
```

Within a prefix, suffix with role + index: `pr-ah-01`, `pr-cp-01`, `pr-pa-debtor`, `pr-pa-creditor`, `pr-txn-01`.

---

## What this skill MUST NOT emit

- ExUnit tests (`test/atomic_fi/use_cases/NN_<slug>_test.exs`) — that's P6, a separate human commit
- Bruno collection (`bruno/atomic-fi-financial-crime/NN-<slug>/`) — that's P7, a separate human commit
- Catalog cross-references in `guides/use-cases.md` — that's P8, a separate human commit
- Schema migrations / context code — that's P4, a separate failing-test-first track
- Git commits — the human commits

The skill produces the six files above. Everything else lives outside the slice.
