# Reading a row of `guides/use-cases.md`

The catalog is a flat Markdown table inside the `## Result vocabulary` section. Every row is one scenario. The columns are fixed:

```
   | #  | Scenario              | Result               | Regulations              | Test                          |
   |----|-----------------------|----------------------|--------------------------|-------------------------------|
   | NN | <one-sentence intent> | PASS / BLOCK / …     | <cite 1>; <cite 2>; …    | [link](../path/to/test.exs)   |
```

A "row" is one logical line — even if Markdown wraps it visually, it is one `\n`-terminated record in the file.

---

## Extraction template

For each row the skill must derive five values:

```
   ┌────────────┬─────────────────────────────────────────────────────────┐
   │ row_number │ leading integer in column 1                              │
   │ slug       │ snake_case noun phrase derived from Scenario column     │
   │ rule_type  │ onboarding | transaction-screening  (see § Classifier)  │
   │ verdict    │ accepted | rejected | held   (see § Verdict mapping)    │
   │ schema     │ any new fields/tables the row implies                   │
   └────────────┴─────────────────────────────────────────────────────────┘
```

### slug

The slug is the single identifier the skill carries across:

- `priv/zenrule/<rule_type>/<slug>.json`
- `corpus/zen_rules/<slug>/`
- `.claude/skills/scenario-author/evals/golden/<slug>/`
- `test/atomic_fi/use_cases/NN_<slug>_test.exs`
- `bruno/atomic-fi-financial-crime/NN-<slug>/`

Rules for picking a slug:

- snake_case, lowercase, ASCII only
- 2–4 words, noun phrase (`prohibited_risk_freeze`, not `prohibits_high_risk_holders`)
- include the verdict's distinguishing feature when ambiguous: `ofac_sdn_high_score` (not just `ofac_sdn`), `cip_kyc_in_progress` (not `kyc_block`)
- if a related rule already exists, extend its name rather than colliding: `ofac_mixer_usdc` (extends `stableaml_wallet_blocklist`), not a fresh `mixer_block`

If the slug is unclear, ask the user once.

### Classifier — onboarding vs transaction-screening

```
   The decision is about…              rule_type
   ──────────────────────────────────  ─────────────────────
   the entity (AH / business / BO)     onboarding
   the transaction movement            transaction-screening
```

Heuristics:

- "AH whose X tries to pay any CP" → entity-level → `onboarding`
- "AH pays a CP whose X" → transaction-level → `transaction-screening`
- "Watchman is unreachable when AH originates a payment" → transaction-screening (the engine state is about *this* movement)
- "Business AH with zero BOs" → onboarding (the entity may not transact at all)

### Verdict mapping

```
   guides/use-cases.md Result   →   %Transaction{}.status         rejected_rule (when present)
   ──────────────────────────       ──────────────────────        ─────────────────────────
   PASS                             accepted                       nil
   BLOCK                            rejected                       <slug-derived string>
   BLOCK + OFAC report              rejected                       <slug-derived string>
   REVIEW                           rejected (held)                <slug-derived string>
   REVIEW + SAR-eligible            rejected (held)                <slug-derived string>
   FREEZE                           rejected (held)                <slug-derived string>
   REVIEW (held until …)            rejected (held)                <slug-derived string>
```

The exact `rejected_rule` string is the rule's `_description` band identifier — it must match between the JDM row and the corpus `_expected.rejected_rule`. Pick a stable name and use it everywhere.

### Schema needs

If the row's Scenario column references a field or table that isn't in `references/payload-schema.md`, list it. The skill MUST stop and route the schema add through the failing-test-first migration loop BEFORE drafting the rule.

Examples from the 10 golden scenarios:

```
   #10  AccountHolder.risk_level :prohibited (enum extension)
        + lawful_order_freezes table
   #15  legal_entities.country_of_residence, country_of_birth,
        sanctions_match, sdn_list_entry_id
   #34  transactions.payment_rail, transactions.metadata,
        counterparties.wallet_type, counterparties.chain,
        counterparties.chain_analytics_flag
   #53  audit_events table (hash-chained)
```

If `payload.ex` already covers the row, write "no schema change".

---

## Worked example — row 10

Raw row from `guides/use-cases.md`:

```
   | 10 | AH classified `risk_level = "prohibited"` tries to pay any CP | FREEZE | Internal policy; 31 CFR §1010.230 | [10-prohibited-holder-freeze.test.ts](...) |
```

Derived:

```
   row_number = 10
   slug       = prohibited_risk_freeze
   rule_type  = onboarding
   verdict    = rejected (held), rejected_rule = "prohibited_risk_freeze"
   schema     = AccountHolder.risk_level :prohibited (enum add)
              + lawful_order_freezes table
```

Confirm `(slug, rule_type, verdict)` with the user, then proceed to Step 2.
