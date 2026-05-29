# Payload schema — fields available to a rule

The ZenRule agent evaluates rules against a JSON context built by
`AtomicFi.RuleEngine.Payload.from_transaction/1` (see
`lib/atomic_fi/rule_engine/payload.ex`). Every `inputs[].field` path in
a decision table must resolve in this tree, or the agent will silently
match `null` and your rule will misbehave.

## Top-level shape

```
{
  transaction:               <Transaction or null>,
  account_holder:            <AccountHolder or null>,    // the initiating party
  debtor_payment_account:    <PaymentAccount or null>,   // where money leaves
  creditor_payment_account:  <PaymentAccount or null>,   // where money arrives
  debtor_counterparty:       <Counterparty or null>,     // external sender (if applicable)
  creditor_counterparty:     <Counterparty or null>      // external recipient (if applicable)
}
```

Any branch can be `null` if the association wasn't loaded — your rule
must tolerate that with explicit null-checks in the cell expression
or by ordering rows so the catch-all default fires.

## transaction

Backed by `lib/atomic_fi/transaction_context/transaction.ex`. Common
fields and their JDM `field` paths:

| Field path                              | Type     | Notes                                                                     |
|-----------------------------------------|----------|---------------------------------------------------------------------------|
| `transaction.id`                        | string   | UUID                                                                      |
| `transaction.transaction_type`          | enum     | `"credit_transfer"`, `"direct_debit"`, `"card_payment"`, `"refund"`, `"reversal"`, `"internal_transfer"` |
| `transaction.status`                    | enum     | `"pending"`, `"accepted"`, `"settled"`, `"rejected"`, `"reversed"`, `"cancelled"` |
| `transaction.amount`                    | integer  | Minor units (cents) — `2500` means $25.00                                |
| `transaction.currency`                  | string   | ISO 4217 (`"USD"`, `"EUR"`, …)                                            |
| `transaction.end_to_end_id`             | string   | ISO 20022 reference                                                       |
| `transaction.uetr`                      | string   | SWIFT UETR                                                                |
| `transaction.requested_execution_date`  | date     | YYYY-MM-DD                                                                |
| `transaction.settlement_date`           | date     | YYYY-MM-DD                                                                |

The rule **does not** write outputs under `transaction.*`. The
canonical output shape is described below in **Canonical rule output**.

## account_holder

Backed by `lib/atomic_fi/account_holder_context/account_holder.ex`.

| Field path                          | Type    | Notes                                                                  |
|-------------------------------------|---------|------------------------------------------------------------------------|
| `account_holder.id`                 | string  | UUID                                                                   |
| `account_holder.external_id`        | string  |                                                                        |
| `account_holder.holder_type`        | enum    | `"individual"`, `"business"`, `"trust"`, `"nonprofit"`                  |
| `account_holder.status`             | enum    | `"pending"`, `"active"`, `"suspended"`, `"closed"`, `"flagged"`        |
| `account_holder.kyc_status`         | enum    | `"not_started"`, `"in_progress"`, `"approved"`, `"rejected"`, `"expired"` |
| `account_holder.risk_level`         | enum    | `"low"`, `"medium"`, `"high"`, `"very_high"`                           |
| `account_holder.enabled_currencies` | string[]| e.g. `["USD","EUR"]`                                                   |

## debtor_payment_account / creditor_payment_account

Both share the same shape — `lib/atomic_fi/payment_account_context/payment_account.ex`.

| Field path                                                  | Type    | Notes                                            |
|-------------------------------------------------------------|---------|--------------------------------------------------|
| `<side>_payment_account.id`                                 | string  | UUID                                             |
| `<side>_payment_account.account_type`                       | enum    | `"bank_account"`, `"card"`, `"wallet"`, `"crypto_wallet"` |
| `<side>_payment_account.status`                             | enum    | `"active"`, `"suspended"`, `"blocked"`           |
| `<side>_payment_account.currency`                           | string  | ISO 4217                                         |
| `<side>_payment_account.bank_name`                          | string  |                                                  |
| `<side>_payment_account.iban`                               | string  | sensitive (PCI/PII)                              |
| `<side>_payment_account.country`                            | string  | ISO 3166-1 alpha-2 (e.g. `"US"`, `"KP"`)        |
| `<side>_payment_account.enabled_regimes`                    | string[]| e.g. `["ach_de_minimis","stablecoin_de_minimis"]`|
| `<side>_payment_account.account_holder.kyc_status`          | enum    | nested — same enum as `account_holder.kyc_status`|
| `<side>_payment_account.account_holder.holder_type`         | enum    | nested                                           |
| `<side>_payment_account.account_holder.risk_level`          | enum    | nested                                           |
| `<side>_payment_account.ledger_accounts`                    | LA[]    | nested list — see below                          |

The nested `.account_holder.*` path is the canonical way to check **the
counterparty's KYC**, since `account_holder` at the top level refers
to the initiator. The `de_minimis_genius.json` GENIUS variant uses
`creditor_payment_account.account_holder.kyc_status` to gate stablecoin
de-minimis.

### `<side>_payment_account.ledger_accounts` (LA DAG)

Each PaymentAccount carries its child `LedgerAccount` rows — one per
enabled regime, plus the per-PA root. The rule walks this list to pick
which LA(s) to constrain.

| Field path                                                                | Type    | Notes                                            |
|---------------------------------------------------------------------------|---------|--------------------------------------------------|
| `<side>_payment_account.ledger_accounts[].id`                             | string  | UUID — key the rule output by this               |
| `<side>_payment_account.ledger_accounts[].la_type`                        | enum    | `"account_holder_payment_account_root"`, `"account_holder_payment_account_regime_root"`, `"counter_party_payment_account_root"`, `"counter_party_payment_account_regime_root"` |
| `<side>_payment_account.ledger_accounts[].regime`                         | string  | `"root"` for the PA root, otherwise the regime key (`"ach_de_minimis"`, `"stablecoin_de_minimis"`, …) |
| `<side>_payment_account.ledger_accounts[].currency`                       | string  | ISO 4217                                         |
| `<side>_payment_account.ledger_accounts[].max_daily_debit`                | integer | current per-LA cap (minor units); nil = unconstrained |
| `<side>_payment_account.ledger_accounts[].max_daily_credit`               | integer |                                                  |
| `<side>_payment_account.ledger_accounts[].max_weekly_debit`               | integer |                                                  |
| `<side>_payment_account.ledger_accounts[].max_weekly_credit`              | integer |                                                  |
| `<side>_payment_account.ledger_accounts[].max_monthly_debit`              | integer |                                                  |
| `<side>_payment_account.ledger_accounts[].max_monthly_credit`             | integer |                                                  |
| `<side>_payment_account.ledger_accounts[].max_yearly_debit`               | integer |                                                  |
| `<side>_payment_account.ledger_accounts[].max_yearly_credit`              | integer |                                                  |
| `<side>_payment_account.ledger_accounts[].is_blocked`                     | boolean |                                                  |
| `<side>_payment_account.ledger_accounts[].block_reason`                   | string  | non-nil when `is_blocked` is `true`              |

Pick a leaf by filtering on `regime`:

```
filter(creditor_payment_account.ledger_accounts,
       # .regime == 'stablecoin_de_minimis')[0].id
```

The rule must not assume a specific list order. Always filter.

## debtor_counterparty / creditor_counterparty

External parties — present only when the transaction crosses the
platform boundary. From `lib/atomic_fi/counterparty_context/counterparty.ex`.

| Field path                            | Type    | Notes                                       |
|---------------------------------------|---------|---------------------------------------------|
| `<side>_counterparty.id`              | string  | UUID                                        |
| `<side>_counterparty.status`          | enum    | `"active"`, `"suspended"`, `"blocked"`     |
| `<side>_counterparty.external_id` | string |                                          |

For pure internal_transfer payments (both legs on-platform), both
counterparty branches are `null`. Don't write rules that require them
to exist without a null guard.

---

## How enum values are serialised in cells

Elixir atoms become **JSON strings** when ExOpenApiUtils maps the
struct, and zen_engine expects string-literal cell expressions to be
quoted **inside the JSON string** that holds the expression. So to
match `kyc_status == :approved`:

| In Elixir            | In the request payload   | In a decision-table cell |
|----------------------|--------------------------|--------------------------|
| `:approved`          | `"approved"`             | `"\"approved\""`         |
| `:credit_transfer`   | `"credit_transfer"`      | `"\"credit_transfer\""`  |

If you forget the inner quotes the cell becomes a variable reference,
not a literal, and matching breaks silently. The cheatsheet has more
examples.

## Canonical rule output

The engine (`AtomicFi.RuleEngine.Default.decode_rule_result/1`) only
honors **one** top-level shape:

```
{
  "ledger_accounts": {
    "<la_uuid>": {
      "daily_debit_cap":    integer | null,
      "daily_credit_cap":   integer | null,
      "weekly_debit_cap":   integer | null,
      "weekly_credit_cap":  integer | null,
      "monthly_debit_cap":  integer | null,
      "monthly_credit_cap": integer | null,
      "yearly_debit_cap":   integer | null,
      "yearly_credit_cap":  integer | null,
      "is_blocked":         boolean,
      "block_reason":       string | null,
      "reason":             string
    },
    "<la_uuid>": { ... }
  },
  "next_screening_at": "<iso8601>" | null
}
```

Anything else (e.g. `transaction.max_amount`, `transaction.rule`) is
**dropped** — the engine treats the rule as having no controls and the
transaction stays `:pending`. Don't author rules that emit
`transaction.*` outputs.

### Per-LA Control attributes

| Field                    | Meaning                                                                     |
|--------------------------|-----------------------------------------------------------------------------|
| `daily_*_cap` … `yearly_*_cap` | Per-period × per-direction caps in minor units. `nil` = unconstrained.  |
| `is_blocked`             | When `true`, the LA itself rejects descendant entries; pair with `block_reason`. |
| `block_reason`           | Required when `is_blocked` is `true`. Surfaces as `rejected_rule` on the voided entry. |
| `reason`                 | Audit string — which rule emitted these caps. Surfaces in `rejected_rule` when a cap is breached. |

Caps **and** `is_blocked` flow to the LedgerAccount row via
`LedgerAccountContext.apply_controls/3`; the trigger then checks every
ancestor LA when an entry lands on a descendant. The rule may target
**any** LA in the DAG (leaf, parent, regime-root, AH-root) — the engine
does not assume "leaf".

### Computed-key output

Decision-table outputs only support static dotted paths. To key
`ledger_accounts` by an LA UUID resolved from the payload, use an
`expressionNode` so the key is computed:

```json
{
  "id": "out",
  "type": "expressionNode",
  "content": {
    "expressions": [
      { "key": "ledger_accounts",
        "value": "{
          [filter(creditor_payment_account.ledger_accounts,
                  # .regime == 'stablecoin_de_minimis')[0].id]:
            creditor_payment_account.account_holder.kyc_status == 'approved'
              ? { reason: 'stablecoin_de_minimis' }
              : { is_blocked: true,
                  block_reason: 'stablecoin_block_unverified',
                  reason: 'stablecoin_block_unverified' }
        }"
      }
    ]
  }
}
```

A decision table can sit **upstream** of the expression node to fan
into per-branch logic via `switchNode`, but the final emitter of the
`ledger_accounts` map is an expression because it needs a computed key.

## What you can't do (yet)

The Payload module currently only knows how to build context for a
**Transaction**. `from_entity/1` falls through to a plain
`Mapper.to_map/1` for anything else, so rules keyed off other entity
types are not wired up. Don't author rules that assume e.g. a
LedgerEntry root.
