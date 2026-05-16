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

Output-only fields the rule typically writes (via `outputs[].field`):
`transaction.rule`, `transaction.max_amount`, `transaction.daily_debit_limit`,
`transaction.weekly_debit_limit`, `transaction.monthly_debit_limit`,
`transaction.yearly_debit_limit`, `transaction.daily_credit_limit`,
`transaction.weekly_credit_limit`, `transaction.monthly_credit_limit`,
`transaction.yearly_credit_limit`. These are convention from the
existing `de_minimis.json` rule — you can introduce new output names if
the downstream consumer (`AtomicFi.ZenRule.HttpClient.get_limits/1`)
agrees.

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
| `<side>_payment_account.account_holder.kyc_status`          | enum    | nested — same enum as `account_holder.kyc_status`|
| `<side>_payment_account.account_holder.holder_type`         | enum    | nested                                           |
| `<side>_payment_account.account_holder.risk_level`          | enum    | nested                                           |

The nested `.account_holder.*` path is the canonical way to check **the
counterparty's KYC**, since `account_holder` at the top level refers
to the initiator. The `de_minimis_genius.json` GENIUS variant uses
`creditor_payment_account.account_holder.kyc_status` to gate stablecoin
de-minimis.

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

## What you can't do (yet)

The Payload module currently only knows how to build context for a
**Transaction**. `from_entity/1` falls through to a plain
`Mapper.to_map/1` for anything else, so rules keyed off other entity
types are not wired up. Don't author rules that assume e.g. a
LedgerEntry root.
