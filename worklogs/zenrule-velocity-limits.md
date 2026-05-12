# Handover — ZenRule velocity limits

> **Read this top to bottom before touching code.** It is a full handover for a fresh
> Claude Code session: the why, the architecture, what's done, what's left, the
> decisions that already flip-flopped (don't re-open them), the gotchas, and how the
> human you'll be working with operates.

---

## 0. TL;DR

We're integrating **ZenRule** — the open-source [GoRules Agent](https://github.com/gorules/agent-public),
a headless rules engine over REST — as atomic-fi's risk/limits engine. It returns
**velocity limits** (daily/weekly/monthly/yearly × debit/credit caps) for the **ledger
accounts** involved in a transaction (or created at onboarding). Those limits get
written onto `ledger_entries.limits_at_entry`; a PostgreSQL trigger fans them up the
ledger-account ancestor chain into the flat `last_*_limit` columns on
`ledger_account_balances`, where 8 CHECK constraints enforce them; on a breach the
trigger marks the entry `:voided` with structured `rejected_*` metadata, and the
transaction ends up `:rejected`.

Started as "a deliberately minimal TDD with ZenRule"; grew into a ledger-subsystem
reshape because limits are inherently ledger-account-scoped, not transaction-scoped.

**Status:** ZenRule local stack + the schema layer + `create_entries`/`create_transaction`
are committed and compile; migrations install cleanly. **Not yet working end-to-end** —
onboarding doesn't create the ledger-account tree yet, the JDM decision is the old shape,
and `mix test` is red (existing ledger/txn tests + `assert_schema` specs reference dropped
columns). See §5–§6.

---

## 1. How to resume

- **Branch:** `feat/issue-27-block-1-scenarios`
- **HEAD as of this handover:** `5c8ca7c` — resume on top of it.

```bash
# ZenRule (GoRules Agent) — built locally from the vendored subtree (no arm64 image upstream):
docker compose -f local-dependencies.yaml up -d zenrule        # listens on :8090; or `make run-backing-services`
docker compose -f local-dependencies.yaml build zenrule        # rebuild it (rare; LTO-off Rust build, ~few min cold)

# DB / build:
MIX_ENV=test mix ecto.reset      # rebuild the test DB — migrations install cleanly TODAY
mix compile                      # green TODAY
mix test                         # RED TODAY (see §6 H — existing ledger/txn tests + assert_schema specs)

# ZenRule smoke (the de_minimis.json decision is currently the OLD shape — rewrite is step G):
curl -s -XPOST localhost:8090/api/projects/atomic-fi/evaluate/de_minimis.json \
  -H 'content-type: application/json' -d '{"context":{"transaction":{"transaction_type":"credit_transfer"}}}'
```

Tests hit the **real local ZenRule container** (`config/test.exs` → `:zen_rule_base_url` =
`http://localhost:8090`), mirroring how the Watchman tests hit the local Watchman container.

Commits, oldest→newest:

| commit | what |
|---|---|
| `d2f6c05` | ZenRule local stack: `external-deps/zenrule/` git subtree (squashed), `external-deps/zenrule.Dockerfile`, `local-dependencies.yaml` `zenrule` service, `priv/zenrule/atomic-fi/de_minimis.json` (smoke-verified) |
| `6148f82` | schema layer (incl. an early `side` column that `5aa6484` removes) — `velocity_limit` Ecto types, the 3 migrations, schema rewrites, RuleEngine reshape, ZenRule.HttpClient, config |
| `5aa6484` | `LedgerEntryContext.create_entries/3` + `create_transaction` flow; drop `side`; `payment_accounts.enabled_regimes`; the first cut of this worklog |
| `5c8ca7c` | this handover doc |

---

## 2. The journey, and decisions that already flip-flopped (do NOT re-open)

The human is the architect and iterates a lot. Several things were tried and changed.
**These are settled — do not re-litigate them; build to them:**

1. **Limits are ledger-account-scoped, not transaction-scoped.** An early version added
   `transactions.transaction_limit_at_creation` + a `chk_transaction_rule_limit` CHECK on
   the transaction row. That was wrong and was reverted. The transaction only carries the
   *outcome* (`status` + `rejected_*`).
2. **No credit/debit-side ledger accounts.** An interim design had two "master" LedgerAccounts
   per Ledger (one credit-normal, one debit-normal) and a `side` column. Removed. There is
   **one LedgerAccount per `(entity, regime)`**; each LA tracks **both** a cumulative credit
   and a cumulative debit balance (via the existing `ledger_account_balances.{daily,weekly,
   monthly,yearly}_{debit,credit}` columns). `Σ debits = Σ credits` is enforced *at the
   ledger-entry level* (entries are always created in balanced pairs); the hierarchy exists
   only to roll cumulative balances up for the limit checks.
3. **No GAAP `account_type`.** Dropped from `ledger_accounts` — a payments/limits ledger
   doesn't need GAAP classification; nothing enforced on it.
4. **The discriminator is `regime`, not "payment instrument".** Generic string —
   "regulatory regime", "fraud regime", whatever — e.g. `"ach_de_minimis"`,
   `"stablecoin_de_minimis"`. Structural (non-leaf) nodes carry a sentinel: `"_root"` for
   the AccountHolder root LA, `"all"` for a PaymentAccount's umbrella LA.
5. **`ledger_account_balances` is unchanged.** It keeps its 8 flat cumulative columns, 8 flat
   `last_*_limit` columns, and 8 CHECK constraints. (A CHECK can't iterate an array, so the
   limit columns the CHECKs reference must stay flat.) Only `ledger_entries` got the array.
6. **Limits travel as a PG composite-type array.** `ledger_entries.limits_at_entry` is
   `velocity_limit[]` where `velocity_limit = (period varchar, direction varchar, cap bigint,
   rule varchar)`. The Ecto types (`VelocityLimitType` / `VelocityLimitArrayType`) are modeled
   on the platform's `Platform.Extensions.Ecto.TokenizedData{,Array}Type`. The trigger fans
   that array into the flat `last_*_limit` columns on each ancestor balance row.
7. **`currency` stays denormalized** on `ledger_accounts` and `ledger_entries` (inherited from
   the Ledger — one Ledger per AccountHolder per currency). Decided "keep" over normalizing.
8. **The CHECK violation is caught in the trigger, not in Elixir.** The trigger is
   `BEFORE INSERT OR UPDATE OF status ON ledger_entries`. It does the balance propagation
   (which trips the `ledger_account_balances` CHECKs on a breach); it wraps that in
   `BEGIN … EXCEPTION WHEN check_violation … END`; on a breach the balance changes roll back
   and the handler sets `NEW.status := 'voided'` + `NEW.rejected_*` (a BEFORE trigger can
   mutate `NEW`). An entry inserted **already** `:voided` is a trigger no-op (used by
   `create_entries` to re-record a rejected pair without moving balances).
9. **Rejection metadata is flat columns, not JSONB.** `rejected_ledger_account_id`,
   `rejected_period`, `rejected_direction`, `rejected_rule`, `rejected_code` — on both
   `ledger_entries` and `transactions`. (An earlier `reason :map` was replaced.)
10. **ZenRule maps `transaction_type → regime`.** atomic-fi does **not** decide the regime —
    it sends ZenRule the full entity tree (incl. the ledger-account ids in play) and ZenRule
    returns limits keyed by the leaf LA ids it picks. `create_transaction`/`create_entries`
    figure out which returned id is the debit leaf vs the credit leaf by matching
    `payment_account_id` (debtor vs creditor) — it does NOT rely on ZenRule tagging side.
11. **HTTP now, NIF later.** Block 1 = `AtomicFi.ZenRule.HttpClient` (a `Req` client over the
    `gorules/agent` container). Block 2 = an in-process NIF over the `zen-engine` Rust crate
    (the agent's subtree is right there at `external-deps/zenrule/`). `priv/zenrule/*.json`
    (the JDM decisions) is the durable artifact across both; `AtomicFi.RuleEngine.Payload`
    (entity → evaluation context, via `ExOpenApiUtils.Mapper`) is shared by both transports.
    Rules-in-DB later: the engine never reads a DB — you'd materialize JDM to a filesystem dir
    / S3 prefix the agent polls (or, with the NIF, hand the bytes straight to it).

---

## 3. Architecture

### 3.1 The pieces

```
                 ┌───────────────────────── atomic-fi ──────────────────────────┐
 client ── HTTP ─► AtomicFiApi.TransactionController ─► TransactionContext.create_transaction
                 │                                          │
                 │                          AtomicFi.RuleEngine (behaviour)
                 │                              impl() = AtomicFi.ZenRule.HttpClient   ── block 2: NIF over zen-engine
                 │                              get_limits(entity) :: {:ok, %{ledger_account_id => [VelocityLimit.t()]}}
                 │                                  │   builds context via AtomicFi.RuleEngine.Payload (ExOpenApiUtils.Mapper)
                 │                                  ▼
                 │           POST <:8090>/api/projects/atomic-fi/evaluate/de_minimis.json  {"context": …}
                 └──────────────────────────────────┬──────────────────────────────────────────────────────┘
                                                    ▼
   ZenRule = gorules/agent (open source, MIT) ──── reads JDM files from priv/zenrule/atomic-fi/*.json
     - no arm64 image upstream → built from a vendored git subtree at external-deps/zenrule/
       via external-deps/zenrule.Dockerfile (LTO disabled so it fits Docker Desktop's ~4GB VM)
     - run by local-dependencies.yaml `zenrule` service (PROVIDER__TYPE=Filesystem, :8090),
       priv/zenrule/ bind-mounted, hot-reloaded on its poll interval
     - de_minimis.json must (after step G) return: {"result": {"ledger_accounts":
         {"<la_id>": [{"period":"weekly","direction":"debit","cap":50000,"rule":"ach_de_minimis"}, …], …}}}
```

### 3.2 The ledger-account hierarchy (one tree per `Ledger`, i.e. per AccountHolder per currency)

```
 Ledger(AccountHolder=Acme, currency=USD)                      a LedgerAccount row carries:
 │                                                               account_holder_id, ledger_id, currency (denormalized)
 ├─ LA  Acme root            regime="_root"  pa=NULL cp=NULL       regime, status, balance (= net credits−debits, trigger-maintained)
 │   ├─ LA PA1 umbrella      regime="all"    pa=PA1  cp=NULL       parent_ledger_account_id, ancestor_ids (uuid[], root-first, system-set)
 │   │   ├─ LA PA1[ach_de_minimis]   regime="ach_de_minimis"  pa=PA1   ← LEAF: ledger_entries land here
 │   │   └─ LA PA1[stablecoin_de_minimis]                      pa=PA1   ← LEAF
 │   └─ LA PA2 umbrella → PA2[…] leaves …                       (one leaf per payment_accounts.enabled_regimes)
 └─ LA  Acme's-counterparty  cp=CP1  pa=NULL                    (Counterparty gets an LA per currency; per-regime leaves under it TBD)
 
 - No `side` column. Each LA has both a cumulative debit and a cumulative credit balance
   (the existing ledger_account_balances columns) — one balance row per (LA, calendar day).
 - Unique (3 partial indexes on ledger_accounts):
     [:ledger_id, :regime]                              WHERE payment_account_id IS NULL AND counterparty_id IS NULL   -- the "_root"
     [:ledger_id, :payment_account_id, :regime]         WHERE payment_account_id IS NOT NULL                            -- "all" + regime leaves
     [:ledger_id, :counterparty_id, :regime]            WHERE counterparty_id IS NOT NULL
 - ledger_entries only ever attach to LEAF LAs; ancestor_ids gives O(1) roll-up for the trigger.
```

### 3.3 Limits storage & enforcement

```
 ledger_entries.limits_at_entry  =  velocity_limit[]   (rule-engine output for THIS entry's leaf LA)
 ledger_account_balances          =  UNCHANGED — 8 flat cumulative cols (daily_debit, daily_credit, …,
                                     yearly_credit) + 8 flat last_*_limit cols + 8 CHECK constraints
                                     (lab_daily_debit_limit: daily_debit <= last_daily_debit_limit, …)

 TRIGGER  propagate_ledger_entry_to_balances   :   BEFORE INSERT OR UPDATE OF status ON ledger_entries
 ────────────────────────────────────────────────────────────────────────────────────────────────────
   INSERT, NEW.status='voided'           → RETURN NEW          (no-op — re-recorded rejected pair)
   INSERT, otherwise                     → propagate +amount, fan limits in
   UPDATE OF status, → 'voided'          → propagate -amount (reverse), fan OLD.limits in
   else                                  → RETURN NEW

   delta := ±NEW.amount on the matching direction
   v_l*_* := the cap pulled out of limits_at_entry[] for each (period, direction)   -- 8 sub-selects from unnest()
   path   := ledger_accounts(NEW.ledger_account_id).ancestor_ids || NEW.ledger_account_id   -- root-first + leaf
   BEGIN
     UPDATE ledger_accounts SET balance += signed(amount) WHERE id = ANY(path)
     FOREACH node_id IN path LOOP
       v_breach_node := node_id                              -- in case the next UPSERT trips a CHECK
       UPSERT ledger_account_balances(node_id, today): bump cumulative daily/weekly/monthly/yearly_<dir>,
         set last_*_limit := COALESCE(<from limits_at_entry[]>, existing)              -- "latest entry wins, NULL keeps"
       -- the 8 CHECKs on ledger_account_balances fire here on a breach
     END LOOP
   EXCEPTION WHEN check_violation THEN
     -- inc/sets rolled back. GET STACKED DIAGNOSTICS CONSTRAINT_NAME e.g. 'lab_weekly_debit_limit'
     NEW.status := 'voided'
     NEW.rejected_ledger_account_id := v_breach_node
     NEW.rejected_period    := split_part(name,'_',2)         -- 'weekly'
     NEW.rejected_direction := split_part(name,'_',3)         -- 'debit'
     NEW.rejected_rule      := (rule from limits_at_entry[] for that period/direction)
     NEW.rejected_code      := 'LIMIT_EXCEEDED'
   END
   RETURN NEW
```

### 3.4 Transaction flow (`TransactionContext.create_transaction/2`)

```
 1. Repo.insert  Transaction  status=:pending
 2. Repo.preload [:account_holder, :debtor_payment_account, :creditor_payment_account,
                  :debtor_counterparty, :creditor_counterparty]                     (@rule_engine_preloads)
 3. RuleEngine.impl().get_limits(transaction)  →  {:ok, %{ledger_account_id => [VelocityLimit.t()]}}
       (HttpClient builds the context via RuleEngine.Payload.from_entity/1, POSTs to ZenRule, decodes)
 4. LedgerEntryContext.create_entries(session, transaction, limits)  →  {:ok, [debit_entry, credit_entry]}
       - resolve_leaf_accounts/2: query ledger_accounts where id ∈ keys(limits) and regime ∉ {"_root","all"};
         debit_la_id = the one with payment_account_id == debtor_payment_account_id; credit_la_id likewise
       - build the pair (status :posted, limits_at_entry = limits[that_la_id]); insert in a Repo.transaction,
         Repo.reload! each (the BEFORE trigger may have flipped status/rejected_*)
       - if either came back :voided → Repo.rollback({:rejected, <its rejected_*>}) → then a 2nd
         Repo.transaction re-inserts BOTH with status=:voided + that rejected_* (trigger no-ops) ⇒ nothing posts
 5. Repo.update  Transaction  with transaction_outcome(entries):
       - all posted ⇒ %{status: :accepted}
       - any voided ⇒ %{status: :rejected, rejected_ledger_account_id/period/direction/rule/code: <from the voided leg>}
```

### 3.5 Onboarding (NOT YET IMPLEMENTED — step D)

Same principle: when an entity is created, build (part of) the LA tree, seeded with rule limits.
- `AccountHolderContext.create_account_holder` → for each `enabled_currencies` Ledger, create the
  `"_root"` LA (`pa=NULL, cp=NULL`).
- `PaymentAccountContext.create_payment_account` → create the PA's `"all"` umbrella LA under the
  AH root, then one regime-leaf LA per `payment_accounts.enabled_regimes` under the umbrella.
- `CounterpartyContext.create_counterparty` → create the CP's LA per currency.
- Seeding limits at create time: mechanism not finalized — likely a zero-amount limit-setting
  ledger entry (so the trigger writes `ledger_account_balances.last_*_limit`), or write the
  balance row's `last_*_limit` directly. (The transaction flow gets fresh limits from `get_limits`
  anyway, so onboarding-seeded limits matter mostly for the very first transaction / for queries.)

---

## 4. File map

**ZenRule local stack** (`d2f6c05`)
- `external-deps/zenrule/` — git subtree of `github.com/gorules/agent-public@main`, `--squash`.
  Update with `git subtree pull --prefix external-deps/zenrule https://github.com/gorules/agent-public.git main --squash`.
- `external-deps/zenrule.Dockerfile` — builds `gorules/agent:local` from the subtree with
  `cargo build --release --config profile.release.lto=false --config profile.release.codegen-units=16`
  (upstream's fat-LTO link OOMs Docker Desktop's ~4 GB VM). Context is `external-deps/`.
- `local-dependencies.yaml` — `zenrule` service: `build: external-deps` / `dockerfile: zenrule.Dockerfile`,
  `8090:8080`, mounts `./priv/zenrule:/home/nonroot/data:ro`, `PROVIDER__TYPE=Filesystem`.
- `priv/zenrule/atomic-fi/de_minimis.json` — the JDM decision. **Currently the OLD shape** (returns
  `{"result": {"transaction": {rule, max_amount, …}}}`); step G rewrites it to the per-LA-id shape (§3.1).

**Ecto types / structs** (`6148f82`)
- `lib/atomic_fi/ledger_account_context/velocity_limit.ex` — `%VelocityLimit{period, direction, cap, rule}` struct.
- `lib/atomic_fi/extensions/ecto/velocity_limit_type.ex` — `Ecto.Type` for the PG `velocity_limit` composite type (4-tuple ↔ struct).
- `lib/atomic_fi/extensions/ecto/velocity_limit_array_type.ex` — `Ecto.Type` for `velocity_limit[]` (delegates per element).

**Migrations** (`6148f82` + `5aa6484` revised `…000001`)
- `priv/repo/migrations/20260511000001_add_rejection_metadata_to_transactions.exs` — `transactions.rejected_*` (+ FK + index).
- `priv/repo/migrations/20260511000002_add_rejection_metadata_to_ledger_entries.exs` — `ledger_entries.rejected_*` (+ FK + index).
- `priv/repo/migrations/20260512000001_reshape_ledger_for_velocity_limits.exs` — `CREATE TYPE velocity_limit`;
  `ledger_accounts`: drop `account_type` (+ its unique), add `regime`/`payment_account_id`/`counterparty_id`,
  3 partial unique indexes; `payment_accounts`: add `enabled_regimes` (text[]); `ledger_entries`: add
  `limits_at_entry velocity_limit[]`, drop the 8 `*_limit_at_entry` int cols; replace the trigger fn +
  re-create the trigger as `BEFORE INSERT OR UPDATE OF status`. `down` raises (one-way reshape).
  **`ledger_account_balances` migration is untouched** — the 8 `last_*_limit` cols + 8 CHECKs stay.

**Schemas** (`6148f82` + `5aa6484`)
- `lib/atomic_fi/ledger_account_context/ledger_account.ex` — `regime`/`payment_account_id`/`counterparty_id`;
  no `side`, no `account_type`; 3 re-keyed `unique_constraint`s; updated `@derive Flop.Schema`, open_api, typedoc.
- `lib/atomic_fi/ledger_entry_context/ledger_entry.ex` — `limits_at_entry` (`VelocityLimitArrayType`, default `[]`);
  `belongs_to :rejected_ledger_account` + `rejected_period/direction/rule/code`; no 8 `*_limit_at_entry`; cast
  includes `rejected_*` (readOnly in OpenAPI — clients can't set them; `create_entries` copies them when voiding).
- `lib/atomic_fi/transaction_context/transaction.ex` — `belongs_to :rejected_ledger_account` + `rejected_*` flat fields.
- `test/support/factory/ledger_account_factory.ex` — `regime: "_root"`; no `side`/`account_type`.
- `lib/atomic_fi/payment_account_context/payment_account.ex` — **needs `enabled_regimes` added** (field + open_api + cast) — NOT done yet.

**RuleEngine** (`6148f82`)
- `lib/atomic_fi/rule_engine.ex` — `@behaviour`; `get_limits(entity) :: {:ok, %{ledger_account_id => [VelocityLimit.t()]}}`; `impl/0` reads `:rule_engine` config.
- `lib/atomic_fi/rule_engine/payload.ex` — `from_entity/1` / `from_transaction/1`: entity → JSON-able context map via `ExOpenApiUtils.Mapper`. **Needs enrichment** with the resolved leaf LA ids (query `ledger_accounts` for the debtor/creditor PAs) so ZenRule can key its response by them — NOT done yet.
- `lib/atomic_fi/zen_rule/http_client.ex` — `@behaviour AtomicFi.RuleEngine`; `Req.post` to `/api/projects/atomic-fi/evaluate/de_minimis.json`; decodes `{"result": {"ledger_accounts": {"<id>": [<line>…]}}}` → `%{id => [VelocityLimit]}`. Pattern follows `AtomicFi.Watchman.Client`.

**Contexts** (`5aa6484`)
- `lib/atomic_fi/ledger_entry_context.ex` — `create_entries/3` + helpers (`resolve_leaf_accounts/2`,
  `find_leaf/2`, `entry_attrs/4`, `insert_entry!/2` [uses `Repo.reload!`], `rejection_from/2`, `voided_overrides/1`);
  moduledoc rewritten for the BEFORE trigger.
- `lib/atomic_fi/transaction_context.ex` — `create_transaction/2` rewrite (`with` pipeline §3.4) + `transaction_outcome/1` + `@rule_engine_preloads`.

**Config** (`6148f82`)
- `config/config.exs` / `config/test.exs` — `:zen_rule_base_url` = `"http://localhost:8090"`, `:rule_engine` = `AtomicFi.ZenRule.HttpClient`.
- `config/runtime.exs` — `config_env() == :prod`: `:zen_rule_base_url` from `ZEN_RULE_URL` (raises if missing).

---

## 5. What's done & validated

- ZenRule local stack — built, runs, smoke-curled (OLD JDM shape). (`d2f6c05`)
- Schema layer — Ecto types, the 3 migrations, schema rewrites, RuleEngine/Payload/HttpClient, config. (`6148f82`)
- `LedgerEntryContext.create_entries/3` + `TransactionContext.create_transaction/2` rewrite. (`5aa6484`)
- `mix compile` green. `MIX_ENV=test mix ecto.reset` green (migrations install cleanly — composite type, the 3 alters, the BEFORE trigger all create OK).

## 6. What's left (in rough dependency order)

**D — onboarding LA-tree creation** *(blocking — without it, a transaction's PaymentAccounts have no leaf LAs)*
- `PaymentAccount`: add `enabled_regimes` (`{:array, :string}`) — schema field + `open_api_property` + cast + factory default `[]`.
- `AccountHolderContext.create_account_holder` → after insert, for each enabled-currency Ledger (the AccountHolder
  schema has `enabled_currencies`; Ledgers are presumably already created elsewhere — check), create the `"_root"`
  LA (`pa=NULL, cp=NULL, regime="_root", parent=nil, ancestor_ids=[]`).
- `PaymentAccountContext.create_payment_account` → after insert, create the PA's `"all"` umbrella LA (parent = the
  AH root LA for that ledger, `regime="all"`, `payment_account_id=PA.id`), then one leaf LA per `enabled_regimes`
  (parent = the umbrella, `regime=<the regime>`, `payment_account_id=PA.id`). Use the existing
  `LedgerAccountContext.create_ledger_account` (which computes `ancestor_ids` from the parent) — or replicate that.
- `CounterpartyContext.create_counterparty` → create the CP's LA per currency (`counterparty_id=CP.id`).
- Seed limits at create time (mechanism TBD — see §3.5 / §8). For the MVP it may be acceptable to *not* seed and
  let the first transaction's `get_limits` populate them; if so, document that.
- `RuleEngine.Payload.from_transaction` enrichment — include the debtor/creditor PAs' leaf LA ids in the context
  (`%{ledger_accounts: [%{id, payment_account_id, regime}, …]}` alongside the entity maps). It already aliases
  `AtomicFi.TransactionContext.Transaction`; add `alias AtomicFi.Repo` + a small query.

**G — rewrite the JDM** — `priv/zenrule/atomic-fi/de_minimis.json` so the decision returns
`{"result": {"ledger_accounts": {"<la_id>": [{"period":"weekly","direction":"debit","cap":50000,"rule":"ach_de_minimis"}, …], …}}}`.
Input context has the entity tree (incl. `ledger_accounts: [{id, payment_account_id, regime}, …]`); the decision
maps `transaction.transaction_type → regime`, picks the matching leaf LA id for the debtor side (debit caps) and
the creditor side (credit caps), and emits the lines keyed by those ids. JDM = GoRules JSON Decision Model
(`nodes`/`edges`; decision-table, expression, function nodes). Free online editor: editor.gorules.io. The current
file is a working JDM (single decision table) — adapt it. Confirm the actual de-minimis thresholds + regime names
with the human (the existing file's `2500` / `"ach_de_minimis"` / `"stablecoin_de_minimis"` were placeholders).

**H — tests**
- `test/atomic_fi/transaction_context_zen_rule_test.exs` (NEW) — context-layer TDD spec: ExMachina factory builds
  tenant → legal_entity → account_holder → payment_accounts (with `enabled_regimes`) → counterparties; the
  onboarding hooks (D) create the LA trees; then `TransactionContext.create_transaction(session, request)` for an
  amount at the de-minimis threshold → `{:ok, %Transaction{status: :accepted}}` and the ledger entries posted; for
  an amount over it → `{:ok, %Transaction{status: :rejected, rejected_rule: …, rejected_period: …}}` and both
  entries `:voided`. Use `AtomicFi.DataCase`. (Tests hit the real ZenRule container — `make run-backing-services`.)
- `test/atomic_fi_api/controllers/transaction_controller_test.exs` — add a `describe "create — rule engine limits"`
  block following the existing pattern (`setup :setup_platform_admin_api`, `import OpenApiSpex.TestAssertions`,
  `assert_schema(response, "TransactionResponse", ApiSpec.spec())`, `~p"/api/transactions"`). 201 + `status: "accepted"`
  for under-limit; 422 (or 200 with `status: "rejected"` + `rejected_*` — decide which the controller should do;
  `{:ok, %Transaction{status: :rejected}}` currently flows to a 201/200, not a 422 — confirm desired behaviour) for over.
- `integration-tests/tests/zen_rules.test.ts` (NEW) — vitest, only after the Elixir tests pass: `beforeAll` builds
  the entity graph via the API; POST transactions with hardcoded amounts; assert `status` + `rejected_rule` in the
  response. No GET-limits call. `afterAll` cleans up.
- **Fix the existing tests/specs that reference dropped columns** — run `mix test` to enumerate; expect breakage in
  ledger-account / ledger-entry / ledger-account-balance context tests, transaction tests, and the OpenAPI
  `assert_schema` specs (`account_type`, `*_limit_at_entry`, `last_*_limit` are gone; `side` was never in a release;
  `regime`, `limits_at_entry`, `rejected_*`, `enabled_regimes` are new). Update factories where needed.

**VERIFY** — `mix test` green; `cd integration-tests && TARGET_ENV=local npx vitest run tests/zen_rules.test.ts`.
Also run `mix format` / `mix credo --strict` before committing (project convention; commits are `-S` GPG-signed,
conventional-commit messages). And consider committing in reviewable increments (the human asked for that).

---

## 7. Open questions / decisions still needed

- **Onboarding limit-seeding mechanism** — zero-amount limit-setting ledger entry vs. writing
  `ledger_account_balances.last_*_limit` directly vs. don't seed (let the first txn populate). Ask.
- **Rejected-transaction HTTP status** — `create_transaction` returns `{:ok, %Transaction{status: :rejected}}` on a
  limit breach (not `{:error, changeset}`). Should the controller render that as 201/200 with `status: "rejected"`,
  or translate it to 422? Earlier discussion leaned toward "blocked ⇒ surfaces as a changeset error / 422", but the
  final flow makes it `{:ok, rejected_txn}`. Confirm.
- **Counterparty regime leaves** — does a Counterparty's LA also get per-regime leaf children (like a PaymentAccount),
  or just one LA per currency? §3.2 currently assumes the latter. Ask.
- **`PaymentAccount.ledger_account_id`** — the schema still has the old single FK. With per-regime LAs it's ambiguous
  (which LA?). Either repoint it at the PA's `"all"` umbrella LA, or deprecate it. Ask / decide.
- **De-minimis thresholds & regime names** in the JDM — the current `2500` / `"ach_de_minimis"` /
  `"stablecoin_de_minimis"` are placeholders. Confirm with the human / the ZenRule container's intended config.

---

## 8. Gotchas / risks

- **Trigger runtime correctness is unverified** — it migrates fine, but no ledger entry has actually inserted in a
  test yet. Watch: `GET STACKED DIAGNOSTICS CONSTRAINT_NAME` + `split_part(name,'_',2/3)` parsing of
  `lab_<period>_<direction>_limit`; `unnest(velocity_limit[])` sub-selects; the savepoint scoping of the one big
  `EXCEPTION` block (it must wrap the whole FOREACH so a breach on the Nth ancestor rolls back ancestors 1..N).
- **Postgrex composite-type round-trip** — Postgrex auto-introspects `velocity_limit` at connect time and
  decodes/encodes it as a 4-tuple (this is exactly the platform `TokenizedData` pattern). The type must exist before
  the connection pool connects → fine for `mix test` (migrations run first) and after `mix ecto.migrate` + restart,
  but if you hit a "type velocity_limit does not exist" decode error, the pool connected before the migration.
- **`create_entries` re-read** — `Repo.insert!` does NOT return trigger-mutated columns by default, so `insert_entry!/2`
  does `Repo.reload!` after insert to see `status`/`rejected_*`. (Alternative: mark those `read_after_writes: true`
  on `LedgerEntry` — not done.)
- **`mix compile` prints nothing in this environment even when it recompiles** — don't read "no output" as "didn't
  run". Errors *do* print. Use `mix compile --force 2>&1 | grep -i error` if unsure.
- **`mix compile` doesn't validate migrations or `test/`** — only `mix ecto.migrate` / `mix test` exercise the
  migration SQL and the factories.
- **The `transaction_context.ex` you might see in `git log` flip-flopped** — it was reverted to the original at one
  point (the early `transaction_limit_at_creation` approach was backed out) then rewritten as in `5aa6484`.

---

## 9. How the human you're working with operates (read this)

- **They are the architect and iterate heavily.** Expect the design to be refined as you go. When they correct
  something, build to the correction — don't argue it back.
- **Do NOT make significant design changes without approval.** This was an explicit and repeated complaint. If the
  plan doesn't cover something, ask — concisely — rather than guessing. (The one big self-made call here, adding
  `side`, was reverted.)
- **Keep messages tight; use ASCII diagrams for anything structural.** They said "too many words" more than once.
  Tables and box-diagrams over prose.
- **Reuse existing patterns.** `ExOpenApiUtils.Mapper` for entity→map; the platform's `TokenizedData{,Array}Type`
  for the composite-type Ecto types; the `AtomicFi.Watchman.Client` shape for the ZenRule HTTP client; the
  `def_with_rls_and_logging` macro + `session:`-scoped `Repo` calls (or `skip_multi_tenancy_check: true` for
  preloads, per the codebase convention); `assert_schema` + `~p` + `setup :setup_platform_admin_api` in controller
  tests.
- **Commit incrementally** (they asked for it), `-S` GPG-signed, conventional-commit messages, `mix format` /
  `mix credo --strict` first. The repo is the moved `alvera-ai/atomic-fi` (origin still says
  `payments-compliance-platform` — `git push` warns about it; harmless).
- **Keep this worklog updated** as you go — that's the whole point of it.
