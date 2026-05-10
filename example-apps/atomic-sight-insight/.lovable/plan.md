# Rules Engine — v1

A declarative, in-browser rules engine that evaluates every transaction and account holder, surfaces breaches with a confidence score, and lets users author/test/promote rules through a sandbox → live → archived lifecycle.

## Model

```ts
type RuleScope = "transaction" | "account_holder";
type RuleStatus = "sandbox" | "live" | "archived";
type RuleSeverity = "low" | "medium" | "high" | "critical";
type RuleAction = "flag" | "review" | "block";

type Operator =
  | "eq" | "neq" | "in" | "not_in"
  | "gt" | "gte" | "lt" | "lte"
  | "between" | "contains" | "exists" | "matches_list";

interface Condition {
  id: string;
  field: string;        // e.g. "amount", "currency", "counterparty.status", "account_holder.risk_level"
  operator: Operator;
  value: unknown;
  weight: number;       // 1–10, contributes to confidence
}

interface ConditionGroup {
  id: string;
  combinator: "AND" | "OR";
  conditions: (Condition | ConditionGroup)[];
}

interface Rule {
  id: string;
  name: string;
  description: string;
  scope: RuleScope;
  status: RuleStatus;
  severity: RuleSeverity;
  action: RuleAction;
  threshold: number;    // 0–1; hit only fires if confidence ≥ threshold
  when: ConditionGroup;
  tags: string[];
  created_at: string;
  updated_at: string;
  created_by: string;
  version: number;
}

interface RuleHit {
  id: string;
  rule_id: string;
  rule_version: number;
  rule_name: string;
  severity: RuleSeverity;
  action: RuleAction;
  subject_type: RuleScope;
  subject_id: string;
  confidence: number;          // 0–1
  matched_conditions: { field: string; operator: Operator; value: unknown; matched: boolean; weight: number }[];
  evaluated_at: string;
  mode: "live" | "sandbox";    // sandbox hits never affect production state
}
```

**Confidence**: `sum(weight of matched leaf conditions) / sum(weight of all leaf conditions)`. AND/OR groups gate whether the rule "fires" at all (group must evaluate true), but the confidence reflects breadth of match. Predictable, explainable, no ML.

## Engine

`src/lib/rules/engine.ts`:
- `evaluate(rule, fact)` → `RuleHit | null`
- `evaluateAll(rules, fact, mode)` → `RuleHit[]`
- `buildFact(transaction)` and `buildFact(accountHolder)` resolvers that flatten linked entities (counterparty, holder, screening) into a dotted-path fact object so conditions can reference `creditor_counterparty.status`, `account_holder.risk_level`, `latest_screening.status`, etc.

Triggers (mock):
- `listTransactions` / `getTransaction` → run live transaction rules, attach hits to result.
- `updateTransaction`, `updateAccountHolder`, `updateKycRequirement` → re-evaluate, persist hits.
- On rule save with `status: live` → backfill hits across the store.

A `useRuleHits(subjectType, subjectId)` hook reads from an in-memory `hitStore` keyed by subject.

## Rule lifecycle

- **sandbox**: editable, runs only on demand in the sandbox screen, writes to a separate `sandboxHitStore`. Never appears on transaction/holder panes.
- **live**: read-mostly (edits bump `version` and re-backfill), evaluated on every fact change, hits surface inline.
- **archived**: hidden from evaluation, preserved for audit. Promote back via "Restore to sandbox".

Transitions: `sandbox → live` (Promote), `live → archived` (Archive), `archived → sandbox` (Restore). Each transition is a single action with a confirm dialog; no version branching in v1.

## Screens

### New: `/rules` (Compliance group, sidebar)

```text
+--------------------------------------------------------------+
| Tabs: [ Live (n) ] [ Sandbox (n) ] [ Archived (n) ]          |
| [ + New rule ]   [ Search ]   [ Scope ▾ ] [ Severity ▾ ]     |
+--------------------------------------------------------------+
| Rules table                                                  |
|  name | scope | severity | action | hits (7d) | updated      |
|   …row click → rule editor drawer                            |
+--------------------------------------------------------------+
```

**Rule editor drawer** (right Sheet, ~640px):
- Header: name, status pill, Promote/Archive/Restore button.
- Tabs:
  1. **Definition** — visual condition builder (field picker driven by scope-specific schema, operator dropdown, value input typed by field, weight slider 1–10, AND/OR groups, nestable). "View JSON" toggle swaps to a read-only JSON view with copy button.
  2. **Settings** — severity, action, threshold slider, tags, description.
  3. **Sandbox** — slice picker (date range over `settlement_date`/`inserted_at`, status multi-select, optional sample cap) + Run button. Results: hit count, hit rate, confidence histogram, table of matched subjects with per-condition breakdown. "Compare vs live" toggle diffs hits against currently-live rules of the same scope.
  4. **History** — version log (created, edited, promoted, archived) with diff of `when` between versions.

### Modified: Transaction detail pane (Screen 1) and Onboarding holder pane (Screen 2)

- **Banner** at top of pane when any live hit has confidence ≥ 0.8 OR severity ∈ {high, critical}: red/amber strip with rule name, confidence, and "View" link.
- **New "Rule hits" tab** (added to existing tabs): full list of live hits, each expandable to show every condition with matched/unmatched + weight contribution.

### Modified: Recommendations (Screen 6)

Add a new `kind: "create_rule_from_pattern"` recommendation that, when approved, opens the rule editor drawer pre-filled with conditions derived from the platform signal.

## Field schema (drives the visual builder)

`src/lib/rules/schema.ts` exports per-scope field metadata:

```ts
{
  transaction: [
    { path: "amount", label: "Amount (minor units)", type: "number" },
    { path: "currency", label: "Currency", type: "enum", values: ["USD","EUR","GBP","JPY"] },
    { path: "status", label: "Status", type: "enum", values: [...TransactionStatus] },
    { path: "transaction_type", label: "Type", type: "enum", values: [...TransactionType] },
    { path: "creditor_counterparty.status", label: "Creditor status", type: "enum", values: [...CounterpartyStatus] },
    { path: "creditor_counterparty.country", label: "Creditor country", type: "country" },
    { path: "account_holder.risk_level", label: "Holder risk", type: "enum", values: [...RiskLevel] },
    { path: "account_holder.kyc_status", label: "Holder KYC", type: "enum", values: [...KycStatus] },
    { path: "latest_screening.status", label: "Latest screening", type: "enum", values: [...ScreeningStatus] },
  ],
  account_holder: [
    { path: "risk_level", type: "enum", ... },
    { path: "kyc_status", type: "enum", ... },
    { path: "country", type: "country" },
    { path: "entity_type", type: "enum", values: ["individual","business"] },
    { path: "open_kyc_requirements_count", type: "number" },
    { path: "latest_screening.status", type: "enum", ... },
  ]
}
```

The builder reads this to render the right value control (number input, multi-select, country picker, etc.) and to validate.

## Seed rules (so the demo lights up)

Six live + two sandbox + one archived, e.g.:
- "Transfer to blocked counterparty" (transaction, critical, block).
- "High-risk holder over 10k USD" (transaction, high, review).
- "Sanctioned creditor country" (transaction, high, review).
- "Holder KYC not approved" (account_holder, medium, flag).
- "PEP beneficial owner ≥ 25%" (account_holder, high, review).
- "Card payment to suspended counterparty" (transaction, critical, block).
- Sandbox: "Velocity > 5 transfers / 24h" (preview only).
- Archived: "Legacy: any transfer over 100k" (superseded).

## File layout

```
src/lib/rules/
  engine.ts          # evaluate, evaluateAll, fact resolvers
  schema.ts          # per-scope field metadata
  fixtures.ts        # seed rules
  store.ts           # in-memory rules + hit stores, subscribe API
  backtest.ts        # slice picker + run-on-history
src/api/rules.ts     # listRules, getRule, createRule, updateRule, promoteRule, archiveRule, runBacktest
src/api/types.ts     # add Rule, RuleHit, Condition*, etc.
src/pages/RulesPage.tsx
src/components/rules/
  rule-table.tsx
  rule-editor-drawer.tsx
  condition-builder.tsx
  condition-row.tsx
  rule-json-view.tsx
  sandbox-runner.tsx
  hit-explanation.tsx          # per-condition matched/unmatched breakdown
  rule-hit-banner.tsx          # used on tx + holder panes
  rule-hits-tab.tsx            # used on tx + holder panes
```

Wire `/rules` into `App.tsx` and `app-sidebar.tsx` (Compliance group, between Review and Talk to data).

## Out of scope for v1

Rule import/export, scheduled re-evaluation, multi-rule composite scoring, per-tenant rule overrides, real persistence (everything stays in-memory like the rest of the mock layer), approval workflow for promotion (single-click promote with confirm only).
