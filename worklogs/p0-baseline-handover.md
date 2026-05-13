# P0 — Baseline Green Handover

> **Self-contained.** Drop into a fresh session, read top-to-bottom, finish P0, push. No need to grep prior conversation; everything you need to act is in this file.

---

## 1. What you're working on

```
atomic-fi  =  single-tenant, high-performance compliance system of action
              for agents and humans to collaborate on payments compliance.

              • screens parties + transactions against sanctions data
              • enforces velocity limits via a hot-reloadable rule engine
              • records ledger movements via an immutable Postgres trigger
              • KYC is performed UPSTREAM — atomic-fi enforces the verdict,
                never decides it

              Ships in three phases:
                Phase 1 — disconnected demo (laptop install)
                Phase 2 — connected working product (cloud-deployable)
                Phase 3 — alvera-ai/platform connected (workflows on top)

              Source: ~/Downloads/atomic-fi-demo-onepager.md
              (the canonical product framing)

GitHub issue #27  =  Block 1 of the compliance pillar.
                     This handover lives on branch
                     feat/issue-27-block-1-scenarios
```

---

## 2. Milestone table

```
╔═════╦════════════════════════════════════════════════════════╦═══════════╗
║  #  ║  Milestone                                             ║  Status   ║
╠═════╬════════════════════════════════════════════════════════╬═══════════╣
║ P0  ║  Baseline green                                        ║ in flight ║
║     ║    cherry-pick + mix test + vitest + bruno + arch.md   ║ (this doc)║
║     ║    + push                                              ║           ║
╠═════╬════════════════════════════════════════════════════════╬═══════════╣
║ P1  ║  One rule end-to-end  (OFAC SDN)                       ║  blocked  ║
║     ║    skill authors it → simulator runs it → bruno +      ║           ║
║     ║    vitest + context test assert BLOCK + report         ║           ║
╠═════╬════════════════════════════════════════════════════════╬═══════════╣
║ P2  ║  Second rule, same shape  (internal blocklist)         ║  blocked  ║
║     ║    proves the P1 pattern duplicates                    ║           ║
╠═════╬════════════════════════════════════════════════════════╬═══════════╣
║ P3  ║  Remaining 13 screening scenarios                      ║  blocked  ║
║     ║    CIP, PEP, CW, BO, fail-closed, continuing-SAR       ║           ║
╠═════╬════════════════════════════════════════════════════════╬═══════════╣
║ P4  ║  ZenRule velocity expansion                            ║  blocked  ║
║     ║    hard caps, LA tree, per-LA JDM — only when a        ║           ║
║     ║    velocity scenario (#19 / #23) needs it              ║           ║
╠═════╬════════════════════════════════════════════════════════╬═══════════╣
║ P5  ║  Rule library expansion toward 65 + corpus → 1k        ║  blocked  ║
║     ║    bulk-author via the skill, validate via sim         ║           ║
╚═════╩════════════════════════════════════════════════════════╩═══════════╝
```

P0 ships the bicycle frame. Don't drag P1+ work into P0.

---

## 3. Where you are right now

```
repo:    /Users/himangshuhazarika/work/alvera-ai/atomic-fi
branch:  feat/issue-27-block-1-scenarios
HEAD:    a656d27   chore: gitignore .DS_Store + seed example-apps + worklog
remote:  in sync (pushed)

four-layer status
  ✓ Layer 1   mix test         989 / 0           DONE
  ● Layer 2   mix coveralls    89.4% total       SKIP for P0 (polish later)
  ○ Layer 3   pnpm test        not yet re-run    TODO
  ○ Layer 4   bru run          not yet re-run    TODO
  ○           docs/architecture.md               TODO  (content embedded below)
  ○           final commit + push                TODO
```

---

## 4. What this session already did (don't redo)

```
On top of cea609b (prior local HEAD) the session committed:

  a656d27  chore: gitignore .DS_Store + seed example-apps + worklog
  43ae752  refactor(rule_engine): hide impl dispatch behind RuleEngine.get_limits/1
  26ebef0  test(ledger): align fixtures with reshape (regime + limits_at_entry)
  406e8bf  docs(worklog): expand zenrule-velocity-limits into full handover
  9c29be3  docs(worklog): make zenrule-velocity-limits worklog a standalone resume doc
  6799571  feat(ledger): create_entries + create_transaction flow; drop ledger-account
                         side; PA enabled_regimes; worklog
  edc971a  feat(ledger): rule-engine velocity limits — schema layer + RuleEngine
                         behaviour (WIP)

Four cherry-picks (edc971a, 6799571, 9c29be3, 406e8bf) brought in track-B's ZenRule
+ ledger-reshape work that previously lived on origin's tip. Local re-applied
its 13 prior coverage / refactor commits on top.

Production code touched in this session (beyond cherry-picks):

  lib/atomic_fi/rule_engine.ex
    • RuleEngine.get_limits/1 now hides impl dispatch (was: caller did
      RuleEngine.impl().get_limits)
    • Wrapper translates {:ok, %{}} from the impl into {:ok, :no_limits}

  lib/atomic_fi/transaction_context.ex
    • Pattern-matches :no_limits → return the :pending transaction without
      calling create_entries (legacy JDM compat for M1 — no LA tree exists yet)

Test files re-aligned with the reshape:
  test/atomic_fi/ledger_account_context_test.exs
  test/atomic_fi/ledger_account_balance_context_test.exs
  test/atomic_fi/ledger_entry_context_test.exs
  test/atomic_fi_api/controllers/ledger_account_controller_test.exs
```

---

## 5. The reshape, in one diagram

```
ledger_accounts table
  before                                  after
  ──────                                  ─────
  account_type (enum)                     regime (free string)
    :asset (root sentinel)        ────►   "_root"
    :liability / :equity / ...    ────►   any regime name
    unique idx (ledger, type)             partial unique idx (ledger, regime)
                                            WHERE pa_id IS NULL AND cp_id IS NULL

ledger_entries table
  before                                  after
  ──────                                  ─────
  8 × <period>_<direction>_limit_at_entry limits_at_entry velocity_limit[]
    daily_debit_limit_at_entry            (composite-type array:
    daily_credit_limit_at_entry              {period, direction, cap, rule})
    weekly_debit_...                      (none) — fanned into
    ...                                    ledger_account_balances.last_*_limit
                                           by the BEFORE INSERT trigger
                                          + rejected_ledger_account_id
                                          + rejected_period
                                          + rejected_direction
                                          + rejected_rule
                                          + rejected_code

BEFORE INSERT trigger behavior change
  before:  CHECK violation raised Ecto.ConstraintError
  after:   trigger CATCHES check_violation, flips NEW.status := 'voided',
           populates rejected_*. INSERT still succeeds (with :voided row).
           Caller must Repo.reload to see trigger-modified state.
```

---

## 6. P0 — three steps

### Step A: Layer 3 — vitest

```bash
make run-backing-services        # Watchman :8084 + ZenRule :8090
                                 # If ZenRule isn't up:
                                 #   docker compose -f local-dependencies.yaml up -d zenrule

make server &                    # Phoenix :4100 (background)

cd integration-tests
pnpm state:create
pnpm test                        # repair until 235/0 (1 skipped)
cd ..
```

The reshape may have broken specs that assert on:
- `ledger_accounts` response shape (account_type → regime)
- `ledger_entries` response shape (8 cols → 1 composite-array col + 5 rejected_*)
- `transactions` create response (now potentially `:pending`, no longer always
  `:accepted` — `:no_limits` is the M1 fallthrough)

Fix specs to match the new shape. **Do NOT change production code** to satisfy specs.

### Step B: Layer 4 — bruno

```bash
cd bruno/atomic-fi-scenarios
bru run --env local              # expect 29/29 + 66/66 assertions
cd ../..
```

Same fix-pattern. If a bruno request asserts on a removed field, update the assert.

### Step C: docs/architecture.md + final commit + push

```bash
mkdir -p docs
# Write docs/architecture.md with the content from Section 8 below
git add docs/architecture.md integration-tests/tests/ bruno/atomic-fi-scenarios/
git -c commit.gpgsign=true commit -S -m "..."
git push origin feat/issue-27-block-1-scenarios
```

---

## 7. House rules — must follow

```
✗ NEVER  mix test --max-failures        (user forbids — flagged multiple times)
✓ ALWAYS mix test --failed              (one file at a time)
✓ ALWAYS GPG-sign commits (-S flag, conventional commits)
✗ NEVER  add Co-Authored-By trailers
✓ Format ALL chat explanations as ASCII diagrams + ~10 lines max
✗ NEVER  multi-section prose explanations (user said "too verbose")
✓ Test layer order: context → controller → vitest → bruno
  (server-side changes test bottom-up; never jump to bruno first)
✓ Tests fetch via context getters, never manual Repo.preload outside the context
✓ External services (Watchman, ZenRule) are like postgres — hit live in tests
  by default; coveralls-ignore defensive transport branches; Mox seam lives at
  the DOMAIN layer (ScreeningEngine.Behaviour), not the transport layer
✓ For UI/frontend changes: start the dev server + use the feature in a browser
  before claiming success. atomic-fi is API-first; UI lives in atomic-fi-web.
```

---

## 8. Architecture — content for docs/architecture.md

### Product framing (top of architecture.md)

> atomic-fi is a single-tenant, high-performance system of action for agents and humans to collaborate on compliance. Humans author and evaluate rules; agents and applications call the REST API to apply those rules to transactions in real time. KYC is performed upstream — atomic-fi enforces the verdict but never decides it.

### Level 1 — System Context

```
   ┌───────────────────────────┐         ┌───────────────────────────────┐
   │   Compliance Operator     │         │   Agent or Application        │
   │   (human)                 │         │   (machine)                   │
   │   Authors rules in        │         │   Calls REST API to submit    │
   │   English, reviews CSV    │         │   transactions, manage AHs,   │
   │   simulations, enables    │         │   read decisions.             │
   │   rules.                  │         │                               │
   └─────────────┬─────────────┘         └──────────────┬────────────────┘
                 │ writes rules                          │ submits txns
                 └──────────────────┬────────────────────┘
                                    ▼
   ┌────────────────────────────────────────────────────────────────────────┐
   │                       atomic-fi Platform                               │
   │       Single-tenant, high-performance compliance system of action.     │
   └────────────────────────────────────────────────────────────────────────┘
       ▲                ▲                       ▲
       │ KYC verdict    │ sanctions screen      │ rule evaluate
       │                │                       │
   ┌───┴────────┐  ┌────┴─────────────┐  ┌──────┴──────────────┐
   │ Upstream   │  │ Moov Watchman    │  │ GoRules ZenRule     │
   │ KYC System │  │  OFAC SDN, EU,   │  │  JDM rule evaluator │
   │            │  │  UN, FinCEN §311,│  │                     │
   │ sets       │  │  tenant-custom   │  │                     │
   │ kyc_status │  │  watchlists      │  │                     │
   └────────────┘  └──────────────────┘  └─────────────────────┘
```

### Level 2 — Container

```
   ┌────────────────────────────────────────────────────────────────────┐
   │ atomic-fi Platform                                                 │
   │                                                                    │
   │   ┌──────────────────────┐    ┌───────────────────────────────┐   │
   │   │ Phoenix Web App      │───►│ PostgreSQL                    │   │
   │   │ Elixir/OTP, :4100    │    │ RLS multi-tenant, ledger      │   │
   │   │ REST API + Oban +    │    │ BEFORE INSERT trigger         │   │
   │   │ Quantum scheduler    │    │ enforces velocity limits      │   │
   │   └──────┬───────────────┘    └───────────────────────────────┘   │
   │          │ HTTP                                                    │
   │          ▼                                                         │
   │   ┌──────────────┐       ┌────────────────────┐                    │
   │   │ Watchman     │       │ ZenRule            │                    │
   │   │ :8084 (Moov) │       │ :8090 (GoRules)    │                    │
   │   └──────────────┘       │ JDM hot-reload     │                    │
   │                          └────────────────────┘                    │
   └────────────────────────────────────────────────────────────────────┘
            ▲                                     ▲
            │ vitest + bruno                      │ rule authoring
   ┌────────┴────────┐                  ┌─────────┴────────────┐
   │ Test Runners    │                  │ Claude skill + mix   │
   │                 │                  │ atomic_fi.rules.*    │
   └─────────────────┘                  └──────────────────────┘
```

### Level 3 — Components inside Phoenix

```
   ┌────────────────────────────────────────────────────────────┐
   │ Phoenix Web App                                            │
   │                                                            │
   │   Controller Layer                                         │
   │     TransactionController · ComplianceScreeningController  │
   │     AccountHolderController · CounterpartyController       │
   │     PaymentAccountController · BeneficialOwnerController   │
   │     LedgerAccountController · LedgerEntryController        │
   │                            │                               │
   │                            ▼                               │
   │   Context Layer (Ecto)                                     │
   │     TransactionContext · ComplianceScreeningContext        │
   │     AccountHolderContext · CounterpartyContext             │
   │     PaymentAccountContext · BeneficialOwnerContext         │
   │     LedgerEntryContext · LedgerAccountContext              │
   │                            │                               │
   │                            ▼                               │
   │   Decision Engine Layer                                    │
   │     ScreeningEngine.Behaviour                              │
   │       ScreeningEngine          (default impl)              │
   │       ScreeningEngineMock      (per-test override)         │
   │                                                            │
   │     RuleEngine                                             │
   │       ZenRule.HttpClient       (default impl, swappable)   │
   │       wraps impl with :no_limits sentinel                  │
   │                                                            │
   │     BlocklistCache + BlocklistValidator                    │
   │                            │                               │
   │                            ▼                               │
   │     Watchman.Client            ZenRule.HttpClient          │
   │     (plain Req-based)          (plain Req-based)           │
   └────────────────────────────────────────────────────────────┘
```

---

## 9. Settled decisions (don't re-open)

```
KYC                     atomic-fi consumes upstream verdict only
                        (no ingest endpoint, no KYC logic)

HTTP status mapping     200 accepted  /  409 rejected (limit tripped)
                                       /  422 validation error

Rule engine seam        RuleEngine.get_limits/1 (hides impl)
                        emits {:ok, :no_limits} when impl returns {}

Empty-limits path       TransactionContext skips create_entries on
                        :no_limits → transaction stays :pending
                        (M1 compat; deferred until P4 onboarding LA-tree)

Two-layer velocity      hard caps on ledger_accounts (privileged-only)
                        soft caps from ZenRule per-txn
                        trigger evaluates LEAST(hard, soft)
                        — entire concept deferred to P4

JDM thresholds          Block-1 placeholders:
                          ach_de_minimis     = $500 / wk per direction
                          stablecoin_de_min  = $25  / wk per direction

OFAC fixture            Hybrid — real SDN names (Putin, Wagner) for
                        score-band calibration + 1-2 synthetic
                        custom-watchlist entries for edge cases

§1.10 fail-closed       docker stop/start Watchman inside vitest
                        (not a Phoenix dev endpoint)
```

---

## 10. Risks + gotchas

```
1. ZenRule cold-start    container may not start with `make run-backing-services`
                         on first run; explicit `docker compose ... up -d zenrule`
                         was needed in this session.

2. Watchman OFAC ingest  first start downloads ~5min of sanctions lists.
                         subsequent restarts reuse the volume.

3. Trigger reload        create_ledger_entry/2 does NOT Repo.reload after insert
                         (only create_entries/3 does). Tests asserting on
                         trigger-modified status/rejected_* must reload
                         themselves — pattern is documented in
                         test/atomic_fi/ledger_account_balance_context_test.exs

4. PaymentAccount.       still has account_type (bank_account/card/wallet) —
   account_type           this is DIFFERENT from the dropped LA account_type.
                          Don't sed-replace blindly.

5. Postgrex composite    if `mix test` ever fails with
   type race              "type velocity_limit does not exist", run
                          MIX_ENV=test mix ecto.reset
                          and reconnect.

6. Force-push lease      `git push --force-with-lease` was the last push.
                          Don't accept anyone else's force-push on top
                          without rebasing first.
```

---

## 11. P0 done — verify these all green

```bash
mix test                                       # 989 / 0
cd integration-tests && pnpm test && cd ..     # 235 / 0 (1 skipped)
cd bruno/atomic-fi-scenarios && \
  bru run --env local && cd ../..              # 29/29 + 66/66
ls docs/architecture.md                        # exists
git status                                     # clean
git log --oneline -8                           # P0 commits + cherry-pick
                                                #   stack visible
git rev-parse @{upstream}                      # in sync with origin
```

When all green → P0 closed → open a new session for P1 with this doc
plus the parent plan at `~/.claude/plans/handover-issue-abstract-noodle.md`.

---

## 12. Quick references

```
parent plan          ~/.claude/plans/handover-issue-abstract-noodle.md
                     (full 6-milestone plan with verification matrix,
                      block-to-phase mapping, risks; absorbs the onepager)

product onepager     ~/Downloads/atomic-fi-demo-onepager.md
                     (Phase 1 / 2 / 3 capabilities,
                      atomic-fi vs atomic-fi-web vs alvera-ai/platform)

ZenRule worklog      worklogs/zenrule-velocity-limits.md
                     (deep dive on the ledger reshape + per-LA JDM
                      design — read this when starting P4)

original handover    worklogs/issue-27-handover.md
                     (the whole-block plan that preceded the cherry-pick)

issue                https://github.com/alvera-ai/atomic-fi/issues/27
```
