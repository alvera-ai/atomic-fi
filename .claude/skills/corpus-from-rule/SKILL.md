---
name: corpus-from-rule
description: Generates a deterministic test corpus for a ZenRule JDM rule and verifies it against the live atomic-fi write path. Use whenever the user wants to "build fixtures for de_minimis", "generate test data for the SDN rule", "make a corpus for transaction-screening/X", "trust-but-verify this rule", or any phrasing that asks for synthetic payloads paired with expected rule-engine responses. The skill authors four NDJSON files (account_holders, counterparties, payment_accounts, transactions) under `corpus/zen_rules/<rule_corpus>/`, invokes `mix corpus.validate` which inserts each row through the production contexts and creates the transaction (running the full RuleEngine path), then diffs the resulting `%Transaction{}` state against each row's inline `_expected` block. Iterates until convergence.
---

# corpus-from-rule

Turn a ZenRule JDM rule into a deterministic test corpus — four NDJSON files paired with inline expected rule-engine outcomes — verified by running the actual atomic-fi write path and iterating until reality matches the claim.

You are the author and the QA. The user names a rule; you draft the entity graph + transactions with declared verdicts, run `mix corpus.validate`, read the drift report, iterate, commit on convergence.

## When to use

Trigger whenever the user asks for fixtures rooted in a rule:

- "Build a corpus for de_minimis"
- "Generate test payloads for the new SDN screening rule"
- "Trust-but-verify transaction-screening/<rule_id>"
- "Cover this rule with fixtures"

If they only ask whether a rule is correct, run `mix corpus.validate corpus/zen_rules/<rule_corpus>` and report — don't loop.

---

## Corpus folder layout

```
corpus/zen_rules/<rule_corpus>/
  account_holders.ndjson      one AccountHolderRequest row per line; `external_id`
                              is the stable handle. `legal_entity` nested.
  counterparties.ndjson       optional. Reference parent AH via
                              `account_holder_external_id`. The `external_id`
                              field is the stable handle.
  payment_accounts.ndjson     reference parent via `account_holder_external_id`
                              OR `counterparty_external_id`.
  transactions.ndjson         each row carries:
                                - top-level scalars (transaction_type, amount, …)
                                - `*_external_id` keys for all FK refs
                                - inline `_label` { regime, cite, scenario }
                                - inline `_expected` { status, rejected_rule, … }
```

`<rule_corpus>` may differ from the JDM filename — e.g. `de_minimis_stablecoin` is a focused corpus for the part of `de_minimis.json` that covers stablecoin transfers.

The `mix corpus.validate` task walks the four files in FK order (AH → CP → PA → txn), inserts each through the production context, then calls `TransactionContext.create_transaction` for each transaction and diffs the resulting `%Transaction{}` state against the row's `_expected`.

---

## The end-to-end workflow

```
1. READ      → priv/zenrule/<rule_type>/<rule_id>.json + use-cases.md citations
2. CLASSIFY  → onboarding | transaction_screening; expected verdict bands
3. DRAFT     → four ndjson files under corpus/zen_rules/<rule_corpus>/
4. VALIDATE  → make run-backing-services
                mix corpus.validate corpus/zen_rules/<rule_corpus>
5. ITERATE   → for each `mismatch` row: either the payload is wrong (edit
                the ndjson) or the rule is wrong (hand off to zenrule-author).
                Re-run validate.
6. RECORD    → on convergence, commit with conventional commit. Cross-reference
                guides/use-cases.md if the corpus maps to a catalog row.
```

---

## Step 1 — Read

Open the rule:

```
priv/zenrule/<rule_type>/<rule_id>.json
```

Capture: input fields, decision-table rows (each row is a verdict band), `_description` strings (often cite use-case rows).

**Read the shared payload schema** —
`.claude/skills/zenrule-author/references/payload-schema.md` is the
single source of truth for the `AtomicFi.RuleEngine.Payload` shape.
Both skills depend on it; corpus-from-rule never edits it (rule edits
route through `zenrule-author`). Your ndjson must populate every path
the rule reads, via the production write paths.

---

## Step 2 — Classify

Decide:

- **rule_type** — `onboarding` or `transaction_screening`. The directory the rule lives in tells you.
- **Verdict bands** — map each decision-table row to one of `accepted | rejected` (the actual `%Transaction{}.status` values). For `rejected`, include the expected `rejected_rule` string.

Example for a stablecoin-block variant of de_minimis:
- recipient KYC-approved → `status: accepted`
- recipient KYC-pending + stablecoin → `status: rejected, rejected_rule: "stablecoin_block_unverified"`
- recipient KYC-pending + ACH over cap → `status: rejected, rejected_rule: "ach_de_minimis"`

---

## Step 3 — Draft

Four ndjson files. One row per AH/CP/PA/txn. Each `external_id` is a stable handle; `*_external_id` keys reference handles.

`account_holders.ndjson` row (must set `status: "pending"` and `risk_level` because nil overrides Ecto defaults):

```jsonl
{"external_id":"dms-ah-sender","holder_type":"individual","status":"pending","kyc_status":"approved","risk_level":"low","enabled_currencies":["USD"],"legal_entity":{"legal_entity_type":"individual","first_name":"Alice","last_name":"Sender"}}
```

`payment_accounts.ndjson` row:

```jsonl
{"external_id":"dms-pa-sender","account_holder_external_id":"dms-ah-sender","account_type":"wallet","currency":"USD"}
```

`transactions.ndjson` row:

```jsonl
{"external_id":"dms-txn-01","transaction_type":"internal_transfer","amount":10000,"currency":"USD","account_holder_external_id":"dms-ah-sender","debtor_external_id":"dms-pa-sender","creditor_external_id":"dms-pa-creditor-verified","_label":{"regime":"aml-cip","cite":"31 CFR §1020.220","scenario":"recipient verified, small stablecoin"},"_expected":{"status":"accepted","rejected_rule":null}}
```

Use unique handle prefixes per corpus (`dms-` for de_minimis_stablecoin) so reruns don't clash with siblings.

---

## Step 4 — Validate

Bring backing services up if they aren't:

```sh
make run-backing-services
```

Run:

```sh
mix corpus.validate corpus/zen_rules/<rule_corpus>
```

The task prints per-row progress as it inserts AHs/CPs/PAs/txns, then a markdown report at the end:

- `match` — `_expected` matches actual `%Transaction{}` state
- `new` — no `_expected` block on the row; actual captured for the human to review
- `mismatch` — diff shown
- `setup_error` — context create returned an Ecto changeset error; payload is wrong
- `engine_error` — `TransactionContext.create_transaction` errored; usually rule engine reachability or shape

---

## Step 5 — Iterate

Mismatches mean either:

- **the payload is wrong** — edit the ndjson row to better exercise the band. Re-run validate.
- **the rule is wrong** — hand off to `zenrule-author` to extend the JDM. Re-run validate.

Don't edit rules from this skill. Stay on corpus authoring.

---

## Step 6 — Record (the proof artifact)

On full convergence, emit a **deterministic, committable proof** of the
run alongside the corpus and the rule:

```sh
mix corpus.validate corpus/zen_rules/<rule_corpus> --reset \
    --out corpus/zen_rules/<rule_corpus>/proof.md
```

`--reset` drops and re-migrates the `atomic_fi_corpus` Postgres schema
before validating, so the run starts from a clean slate and the
resulting `proof.md` is byte-stable. The proof lives **next to the
corpus that produced it** (not in `priv/zenrule/`, which is reserved
for production-shipped JDM files — the ZenRule agent watches that
directory and chokes on non-`.json` siblings). The proof is **the** acceptance
artifact: a reviewer reads

```
   ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
   │  the JDM rule    │  │  the ndjson      │  │  the proof.md    │
   │  (what it does)  │  │  (what was       │  │  (what happened) │
   │                  │  │   tested)        │  │                  │
   └──────────────────┘  └──────────────────┘  └──────────────────┘
```

side by side without re-running anything.

Commit all three together:

```sh
git commit -S -m "feat(corpus): add fixtures for <rule_corpus>"
```

(staged paths: the ndjson files, the rule edits if any, and the
`<rule>.proof.md`.) Re-running the validate command on a fresh clone
must produce a `git diff <rule>.proof.md` of zero lines — that's what
"reproducible proof" means.

If the corpus maps to rows in `guides/use-cases.md`, add the corpus folder path to that row's Test column in the same commit.

---

## Hard requirements

- **No graceful fallbacks.** A missing required key in any ndjson row crashes the mix task. Loud failure is correct.
- **Deterministic external_ids.** Reruns on the same ndjson must produce the same logical setup. Don't fabricate UUIDs in the ndjson; the contexts assign them on insert.
- **Don't edit rules from here.** Rule edits route through `zenrule-author`.
- **Engine + backing services real.** Mox stubs are for unit tests; this task talks to the live atomic-fi process tree (Postgres + ZenRule + Watchman).

---

---

## Related

- [zenrule-author](../zenrule-author/SKILL.md) — authors the JDM rule files themselves
- [guides/verifying_correctness.md](../../../guides/verifying_correctness.md) — the why and where
- [zenrule-author/references/payload-schema.md](../zenrule-author/references/payload-schema.md) — canonical Payload shape the rule reads from
