# Worklog — ZenRule velocity limits

Rule-engine (ZenRule = the open-source GoRules Agent) driven velocity limits on the
ledger-account hierarchy. Started from "a deliberately minimal TDD with ZenRule"; grew
into a ledger-subsystem reshape.

## Design (locked)

- **ZenRule** = `gorules/agent` (open-source, MIT). No arm64 image upstream → built from a
  vendored git subtree at `external-deps/zenrule/` via `external-deps/zenrule.Dockerfile`
  (LTO disabled so it fits Docker Desktop's ~4 GB VM). Runs from `local-dependencies.yaml`
  on `:8090`, `PROVIDER__TYPE=Filesystem`, rules bind-mounted from `priv/zenrule/`.
- **Transport now** = HTTP (`AtomicFi.ZenRule.HttpClient`, a `Req` client implementing the
  `AtomicFi.RuleEngine` behaviour). **Later (block 2)** = in-process NIF over the `zen-engine`
  Rust crate; `priv/zenrule/*.json` (JDM decisions) is the durable artifact across both, and
  `AtomicFi.RuleEngine.Payload` (entity → evaluation context via `ExOpenApiUtils.Mapper`) is
  shared by both transports.
- **Ledger-account hierarchy** — one tree per Ledger (= per AccountHolder per currency):
  - `AH root LA` (regime `"_root"`, no `payment_account_id`/`counterparty_id`)
  - `PaymentAccount "all"-regime LA` (`payment_account_id` set, regime `"all"`)
  - `PaymentAccount regime-leaf LAs` (`payment_account_id` set, regime e.g. `"ach_de_minimis"`) — one per `payment_accounts.enabled_regimes`
  - `Counterparty LA per currency` (`counterparty_id` set)
  - **No `side`** (credit/debit) — one LA per `(entity, regime)`; each LA tracks both a
    cumulative credit and a cumulative debit balance via the existing
    `ledger_account_balances.{daily,weekly,monthly,yearly}_{debit,credit}` columns.
  - `regime` is generic (regulatory regime, fraud regime, …); `currency` stays denormalized
    on `ledger_accounts`/`ledger_entries` (inherited from the Ledger).
  - Uniqueness: 3 partial unique indexes — `[:ledger_id, :regime]` WHERE pa & cp NULL;
    `[:ledger_id, :payment_account_id, :regime]`; `[:ledger_id, :counterparty_id, :regime]`.
- **Limits storage / enforcement**:
  - `ledger_entries.limits_at_entry` = `velocity_limit[]` (PG composite type
    `(period, direction, cap, rule)`) — the rule-engine output for the entry's leaf LA.
  - `ledger_account_balances` unchanged: 8 flat cumulative cols + 8 flat `last_*_limit` cols
    + 8 CHECK constraints (a CHECK can't iterate an array → limits it references stay flat).
  - Trigger `propagate_ledger_entry_to_balances` → `BEFORE INSERT OR UPDATE OF status`: walks
    `ancestor_ids || self`, bumps the cumulative balances, fans `limits_at_entry[]` into the
    flat `last_*_limit` columns on each ancestor's balance row → the 8 CHECKs fire on a breach
    → the trigger's `EXCEPTION WHEN check_violation` handler persists the entry `:voided` and
    records `rejected_ledger_account_id / rejected_period / rejected_direction / rejected_rule
    / rejected_code` (also denormalized onto `transactions.rejected_*`). An entry inserted
    already `:voided` (the re-insert from `create_entries`) is a trigger no-op.
- **Transaction flow** (`create_transaction`): insert `:pending` → preload (AH, debtor/creditor
  PA + CP) → resolve the LA ids in play → `RuleEngine.get_limits(txn)` → `%{ledger_account_id
  => [VelocityLimit]}` → `LedgerEntryContext.create_entries(...)` posts the balanced pair
  (debit on debtor leaf, credit on creditor leaf, each with its leaf's limits); if either comes
  back `:voided`, re-insert both `:voided` with the same `rejected_*` → update txn `:accepted`
  (or `:rejected` + `rejected_*`). ZenRule maps `transaction_type → regime` and returns limits
  keyed by the leaf LA ids it picks.
- **Onboarding** (same principle): AccountHolder create → root LA; PaymentAccount create →
  "all" LA + one leaf LA per `enabled_regimes`; Counterparty create → LA per currency. Seeded
  with rule limits (TBD: via initial zero-amount limit-setting entries vs. directly).
- **`Σ debits = Σ credits`** holds at the ledger-entry level (entries always created in balanced
  pairs on leaf LAs); the hierarchy exists only to roll cumulative balances up for the checks.

## Status

### Done & validated
- `external-deps/zenrule/` subtree + `external-deps/zenrule.Dockerfile` + `local-dependencies.yaml`
  `zenrule` service; `priv/zenrule/atomic-fi/de_minimis.json` (de-minimis JDM — smoke-verified).
  (commit `d2f6c05`)
- Schema layer (commit `6148f82` + uncommitted `side`-removal / `enabled_regimes` corrections):
  - `velocity_limit` PG composite type + `AtomicFi.LedgerAccountContext.VelocityLimit` struct +
    `AtomicFi.Extensions.Ecto.VelocityLimitType` / `VelocityLimitArrayType`.
  - Migrations: `20260511000001` (transactions `rejected_*`), `20260511000002` (ledger_entries
    `rejected_*`), `20260512000001` (CREATE TYPE; ledger_accounts regime/pa_id/cp_id + 3 partial
    uniques, drop account_type; payment_accounts `enabled_regimes`; ledger_entries `limits_at_entry[]`
    + drop 8 `*_limit_at_entry`; BEFORE-INSERT trigger).
  - Schema rewrites: `LedgerAccount`, `LedgerEntry`, `Transaction`. `ledger_account_factory` fixed.
  - `RuleEngine.get_limits(entity) :: {:ok, %{ledger_account_id => [VelocityLimit.t()]}}`;
    `RuleEngine.Payload`; `ZenRule.HttpClient`. Config: `:zen_rule_base_url` + `:rule_engine`
    (config.exs / test.exs / runtime.exs).
  - `mix compile` green; `MIX_ENV=test mix ecto.reset` green (migrations install cleanly).

### Done (compiling; not yet exercised by tests)
- **E** — `LedgerEntryContext.create_entries/3`: posts the balanced pair on the leaf LAs
  (resolved from `limits`'s keys by `payment_account_id`, excluding `"_root"`/`"all"`), each
  with its leaf's `limits_at_entry`; if either comes back `:voided` (re-read via `Repo.reload!`),
  re-records both `:voided` carrying the same `rejected_*`. (No `read_after_writes` — uses
  `Repo.reload!` after insert. No `cast_limits` helper — `VelocityLimitArrayType.cast/1` already
  passes `[%VelocityLimit{}]` through.)
- **F** — `TransactionContext.create_transaction`: insert `:pending` → preload tree →
  `RuleEngine.impl().get_limits(transaction)` → `LedgerEntryContext.create_entries/3` → update
  txn `:accepted` or `:rejected` + `rejected_*` (from the voided leg). `@rule_engine_preloads`
  added.

### Remaining
- **D** — onboarding LA-tree creation in `AccountHolderContext` / `PaymentAccountContext` /
  `CounterpartyContext` create; `PaymentAccount.enabled_regimes` field/open_api/cast.
  Without this, nothing works — a transaction's PAs have no leaf LAs to land entries on.
- **Payload enrichment** — `RuleEngine.Payload.from_transaction` must include the resolved leaf
  LA ids (query `ledger_accounts` for the debtor/creditor PAs) so ZenRule keys its response by
  them. (`create_entries` already resolves debit/credit leaf from the returned keys; ZenRule just
  needs to know which ids exist.)
- **G** — rewrite `priv/zenrule/atomic-fi/de_minimis.json` to return limits per ledger_account id
  (`{"result": {"ledger_accounts": {"<la_id>": [{period, direction, cap, rule}, …]}}}`).
- **H** — tests: context-layer TDD spec (`test/atomic_fi/transaction_context_zen_rule_test.exs`)
  → controller `describe` block in `transaction_controller_test.exs` (`assert_schema`) →
  vitest `integration-tests/tests/zen_rules.test.ts`. Plus fix the existing ledger/transaction
  tests + OpenAPI `assert_schema` specs that referenced the dropped columns (`account_type`,
  `*_limit_at_entry`, `last_*_limit`).
- **VERIFY** — `mix test` green; `cd integration-tests && TARGET_ENV=local npx vitest run tests/zen_rules.test.ts`.

## Open risks / TBD
- Trigger runtime correctness unverified until an entry actually inserts in tests:
  `GET STACKED DIAGNOSTICS CONSTRAINT_NAME` parsing (`split_part(name, '_', 2/3)` on
  `lab_<period>_<direction>_limit`), `unnest(velocity_limit[])`, the savepoint scoping of the
  big `EXCEPTION` block.
- `velocity_limit` composite-type round-trip through Postgrex (load = 4-tuple, dump = 4-tuple) —
  relies on Postgrex auto-introspecting the type at connect time (works in platform's
  `TokenizedData` pattern; same here, but the type must exist before the pool connects).
- Onboarding "seed limits at create time" — exact mechanism not finalized (zero-amount
  limit-setting entry vs. writing `ledger_account_balances.last_*_limit` directly).
- For `create_transaction`: distinguishing the debit-leaf vs credit-leaf among the la_ids
  ZenRule returns — `create_transaction` resolves debtor-PA's leaves vs creditor-PA's leaves
  itself and uses `get_limits`'s result as a per-la lookup (it does not rely on ZenRule tagging).
