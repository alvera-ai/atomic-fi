// Mirror of .claude/skills/zenrule-author/references/jdm-cheatsheet.md
// Kept in sync manually. Exposed to the agent as a readable so it can
// author valid JDM `content` (decision-table inputs/outputs/rules, cell
// expression syntax, hit policies) without inventing shapes.

export const JDM_CHEATSHEET = `# JDM file syntax — cheatsheet

## File envelope

\`\`\`json
{
  "contentType": "application/vnd.gorules.decision",
  "nodes": [ ... ],
  "edges": [ ... ]
}
\`\`\`

## Node types

| type                | role                                                          |
|---------------------|---------------------------------------------------------------|
| inputNode           | entry point, one per graph, conventionally id "request"       |
| outputNode          | exit point, one per graph, conventionally id "response"       |
| decisionTableNode   | rule body — rows of input/output cells with a hit policy      |
| expressionNode      | single ZEN expression (use sparingly)                         |
| functionNode        | JS code (avoid unless table can't express it)                 |
| switchNode          | branch to different downstream paths (rare)                   |

Every node has at minimum { id, type, name, position: { x, y } }.
Decision/expression/function/switch nodes also carry \`content\`.

Position spacing of ~280px between nodes is what existing rules use.

## Edges

\`\`\`json
{ "id": "edge_<descriptive>", "type": "edge", "sourceId": "<from>", "targetId": "<to>" }
\`\`\`

\`type: "edge"\` is required. The id can be anything unique.

## decisionTableNode content shape

\`\`\`json
{
  "hitPolicy": "first",
  "inputs":  [ <InputColumn>, ... ],
  "outputs": [ <OutputColumn>, ... ],
  "rules":   [ <Row>, ... ]
}
\`\`\`

### inputs[]

\`\`\`json
{
  "id":    "in_<short>",
  "type":  "expression",
  "name":  "Transaction Type",
  "field": "transaction.transaction_type"
}
\`\`\`

The \`field\` must resolve in the payload schema or it will silently match null at evaluation time.

### outputs[]

\`\`\`json
{
  "id":    "out_<short>",
  "type":  "expression",
  "name":  "Decision",
  "field": "transaction.rule"
}
\`\`\`

The agent's response is built by nesting output values under each \`field\` path. For \`transaction.rule\` you get \`{ transaction: { rule: ... } }\`.

### rules[] (the rows)

Each row is a flat object keyed by \`inputs[].id\` for match cells and \`outputs[].id\` for produce cells. Optional \`_id\` and \`_description\` show up in the trace — use them.

\`\`\`json
{
  "_id": "rule_block_kyc_in_progress",
  "_description": "Block payment when payer KYC is still pending",
  "in_kyc_status": "\\"in_progress\\"",
  "out_decision":  "\\"block\\""
}
\`\`\`

### Cell expression syntax — the gotchas

The values are ZEN expressions (small JS-like language). Strings need INNER quotes:

| Want to match…             | Input cell value                                   |
|----------------------------|----------------------------------------------------|
| String equality            | "\\"approved\\""  (quote literal inside JSON string) |
| Numeric equality           | "250"                                              |
| Boolean equality           | "true" / "false"                                   |
| In a set                   | "in [\\"a\\", \\"b\\"]"                            |
| Open range                 | "> 1000" or "< 1000"                               |
| Closed range               | "[1000..5000]" (inclusive) or "(1000..5000)" (exclusive) |
| Null-safe equality         | "$ != null and $ == \\"approved\\"" ($ = current field) |
| Wildcard / always match    | "" (empty string)                                  |

| Want to output…            | Output cell value                                  |
|----------------------------|----------------------------------------------------|
| String literal             | "\\"my_value\\"" (note inner quotes)                |
| Numeric literal            | "10000"                                            |
| Boolean literal            | "true" / "false"                                   |
| Pass-through input         | "transaction.amount" (field ref, unquoted)         |
| Computed                   | "transaction.amount * 1.05"                        |
| Empty (no output this row) | ""                                                 |

The most common bug is forgetting the inner quotes on a string literal — writing "approved" instead of "\\"approved\\"". That parses as a variable name \`approved\` which resolves to null and won't match.

## Hit policies

| hitPolicy   | behaviour                                                                  |
|-------------|----------------------------------------------------------------------------|
| "first"     | First matching row wins. Row order IS the rule. Specific rows before catch-alls; default last. |
| "collect"   | All matching rows collected into an array. Use for enumeration rules.      |

"first" is the right default for most compliance rules.

## Canonical three-node graph

\`\`\`json
{
  "contentType": "application/vnd.gorules.decision",
  "nodes": [
    { "id": "request",   "type": "inputNode",  "name": "Request",  "position": { "x": 100, "y": 160 } },
    {
      "id": "kyc_gate",
      "type": "decisionTableNode",
      "name": "KYC Payment Gate",
      "position": { "x": 380, "y": 160 },
      "content": {
        "hitPolicy": "first",
        "inputs": [
          { "id": "in_kyc", "type": "expression", "name": "KYC Status", "field": "account_holder.kyc_status" }
        ],
        "outputs": [
          { "id": "out_decision", "type": "expression", "name": "Decision", "field": "transaction.rule" }
        ],
        "rules": [
          { "_id": "block_in_progress", "in_kyc": "\\"in_progress\\"", "out_decision": "\\"block\\"" },
          { "_id": "block_rejected",    "in_kyc": "\\"rejected\\"",    "out_decision": "\\"block\\"" },
          { "_id": "review_expired",    "in_kyc": "\\"expired\\"",     "out_decision": "\\"review\\"" },
          { "_id": "default_allow",     "in_kyc": "",                  "out_decision": "\\"allow\\"" }
        ]
      }
    },
    { "id": "response", "type": "outputNode", "name": "Response", "position": { "x": 700, "y": 160 } }
  ],
  "edges": [
    { "id": "e_in",  "type": "edge", "sourceId": "request",  "targetId": "kyc_gate" },
    { "id": "e_out", "type": "edge", "sourceId": "kyc_gate", "targetId": "response" }
  ]
}
\`\`\`
`;
