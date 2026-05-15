# JDM file syntax — cheatsheet

This is a working reference for authoring `.json` decision files that
ZenRule (via `zen_engine`) can evaluate. Source: the existing rules
under `priv/zenrule/atomic-fi/` plus `external-deps/zenrule/`. When in
doubt, the live `de_minimis_genius.json` is the canonical example.

## File envelope

```json
{
  "contentType": "application/vnd.gorules.decision",
  "nodes": [ ... ],
  "edges": [ ... ]
}
```

The `contentType` literal is mandatory — the JDM editor uses it to
recognise the file on Open. Without it, the file loads as raw JSON and
the graph view stays empty.

## Node types you'll author

| `type`               | Role                                                                                          |
|----------------------|-----------------------------------------------------------------------------------------------|
| `inputNode`          | Entry point. One per graph. Conventionally `id: "request"`, `name: "Request"`.                |
| `outputNode`         | Exit point. One per graph. Conventionally `id: "response"`, `name: "Response"`.               |
| `decisionTableNode`  | The rule body — rows of input/output cells with a hit policy.                                 |
| `expressionNode`     | A single ZEN expression (not a table). Use sparingly — tables are easier to read and amend.   |
| `functionNode`       | JS code. Avoid unless a table truly can't express it.                                          |
| `switchNode`         | Branch to different downstream paths. Rare in compliance rules; tables cover most needs.      |

Every node has at minimum `{ id, type, name, position: { x, y } }`.
Decision/expression/function/switch nodes also carry `content`.

Position is `(x, y)` in pixels in the editor canvas. Spacing of
~280px between nodes is what the existing rules use.

## Edges

```json
{ "id": "edge_<descriptive>", "type": "edge", "sourceId": "<from>", "targetId": "<to>" }
```

The `id` doesn't matter at runtime as long as it's unique. `type:"edge"` is required.

## Decision table — the workhorse

```json
{
  "id": "<table-node-id>",
  "type": "decisionTableNode",
  "name": "<Title shown on canvas>",
  "position": { "x": 380, "y": 160 },
  "content": {
    "hitPolicy": "first",          // see below
    "inputs":  [ <InputColumn>, ... ],
    "outputs": [ <OutputColumn>, ... ],
    "rules":   [ <Row>, ... ]
  }
}
```

### `inputs[]`

```json
{
  "id": "in_<short>",                          // unique within the table
  "type": "expression",                        // always "expression" for our rules
  "name": "Transaction Type",                  // human label, shown in the editor
  "field": "transaction.transaction_type"      // path into the payload (see payload-schema.md)
}
```

Each `inputs[]` entry becomes a column. The `field` must resolve in the
runtime context — typos here are silent matches against `null`.

### `outputs[]`

```json
{
  "id": "out_<short>",                         // unique within the table
  "type": "expression",
  "name": "Max Amount",
  "field": "transaction.max_amount"            // path the result lands under in the response
}
```

The agent's response will have a nested object keyed by `field`. For
`transaction.max_amount` the response gets `{ transaction: { max_amount: ... } }`.

### `rules[]` (the rows)

Each row is a flat object keyed by `inputs[].id` (for matching) and
`outputs[].id` (for producing). Plus optional `_id` and `_description`:

```json
{
  "_id": "rule_ach_de_minimis",
  "_description": "ACH credit transfer — de minimis applies regardless of payee KYC (BSA §326 CIP de-minimis)",
  "in_txn_type": "\"credit_transfer\"",         // match value (ZEN expression)
  "in_payee_kyc": "",                           // empty = wildcard (always match)
  "out_rule": "\"ach_de_minimis\"",             // output value (ZEN expression — string literal here)
  "out_max_amount": "2500"                      // output value (numeric literal)
}
```

`_id` and `_description` show up in the trace (`traceData.rule._id`,
`traceData.rule._description`) — use them. Future you will read traces
trying to figure out which row matched; descriptive `_id`s save a lot
of pain.

### Cell expression syntax — the gotchas

The values in each cell are **ZEN expressions** (a small language
similar to JS). The expression's semantics depend on whether it's an
input cell (matching against the field) or an output cell (producing
a value).

| Want to match…                     | Input cell value                                       |
|------------------------------------|--------------------------------------------------------|
| String equality                    | `"\"approved\""` — quote the literal **inside** the JSON string |
| Numeric equality                   | `"250"`                                                |
| Boolean equality                   | `"true"` / `"false"`                                   |
| In a set                           | `"in [\"credit_transfer\", \"direct_debit\"]"`         |
| Open range                         | `"> 1000"` or `"< 1000"`                               |
| Closed range                       | `"[1000..5000]"` (inclusive) or `"(1000..5000)"` (exclusive) |
| Null-safe equality                 | `"$ != null and $ == \"approved\""` (`$` = current field value) |
| Wildcard / always match            | `""` (empty string)                                    |

| Want to output…                    | Output cell value                                      |
|------------------------------------|--------------------------------------------------------|
| String literal                     | `"\"ach_de_minimis\""` (note the inner quotes)         |
| Numeric literal                    | `"10000"`                                              |
| Boolean literal                    | `"true"` / `"false"`                                   |
| Pass-through input                 | `"transaction.amount"` (a field reference, unquoted)   |
| Computed                           | `"transaction.amount * 1.05"`                          |
| Empty (no output for this row)     | `""`                                                   |

The most common authoring bug is forgetting the inner quotes on a
string literal — e.g. writing `"approved"` instead of `"\"approved\""`.
That parses as the **variable name** `approved`, which resolves to
`null`, which won't match anything.

## Hit policies

| `hitPolicy`     | Behaviour                                                                                                |
|-----------------|----------------------------------------------------------------------------------------------------------|
| `"first"`       | First row that matches wins. Row **order is the rule**. Specific rows before catch-alls; default last.  |
| `"collect"`     | All matching rows are collected. Result is an array. Useful for "find all violations".                  |

`"first"` is the right default for most compliance rules. Use
`"collect"` when the rule's purpose is enumeration (e.g. "list every
limit applied", "every sanctions flag triggered").

With `"first"`, watch row ordering: in `de_minimis_genius.json` the
stablecoin-approved row (more specific) precedes the
stablecoin-kyc-required row (catch-all on `internal_transfer`). Flip
those and the approved case becomes unreachable — silently.

## Worked example — minimal three-node graph

```json
{
  "contentType": "application/vnd.gorules.decision",
  "nodes": [
    { "id": "request",   "type": "inputNode",  "name": "Request",  "position": { "x": 100, "y": 160 } },
    {
      "id": "limits",
      "type": "decisionTableNode",
      "name": "Stablecoin KYC Gate",
      "position": { "x": 380, "y": 160 },
      "content": {
        "hitPolicy": "first",
        "inputs": [
          { "id": "in_txn_type",  "type": "expression", "name": "Type",        "field": "transaction.transaction_type" },
          { "id": "in_payee_kyc", "type": "expression", "name": "Payee KYC",   "field": "creditor_payment_account.account_holder.kyc_status" }
        ],
        "outputs": [
          { "id": "out_rule",       "type": "expression", "name": "Rule",       "field": "transaction.rule" },
          { "id": "out_max_amount", "type": "expression", "name": "Max amount", "field": "transaction.max_amount" }
        ],
        "rules": [
          {
            "_id": "rule_stablecoin_approved",
            "_description": "Stablecoin to KYC-approved payee — GENIUS §4(a)(5) carve-out",
            "in_txn_type":  "\"internal_transfer\"",
            "in_payee_kyc": "\"approved\"",
            "out_rule":       "\"stablecoin_de_minimis\"",
            "out_max_amount": "2500"
          },
          {
            "_id": "rule_default",
            "_description": "Anything else — no de-minimis carve-out",
            "in_txn_type":  "",
            "in_payee_kyc": "",
            "out_rule":       "\"default\"",
            "out_max_amount": "0"
          }
        ]
      }
    },
    { "id": "response", "type": "outputNode", "name": "Response", "position": { "x": 700, "y": 160 } }
  ],
  "edges": [
    { "id": "edge_in",  "type": "edge", "sourceId": "request", "targetId": "limits" },
    { "id": "edge_out", "type": "edge", "sourceId": "limits",  "targetId": "response" }
  ]
}
```

This compiles, the agent will pick it up on its next 5s poll, and
`scripts/evaluate.sh <name> '<context>'` will return a trace you can
diff against expected.
