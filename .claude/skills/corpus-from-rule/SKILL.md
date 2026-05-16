---
name: corpus-from-rule
description: Generates a deterministic test corpus for a ZenRule JDM rule and verifies it against the live rule-engine docker. Use whenever the user wants to "build fixtures for de_minimis", "generate test data for the SDN rule", "make a corpus for transaction-screening/X", "trust-but-verify this rule", or any phrasing that asks for synthetic payloads paired with expected rule-engine responses. The skill reads the JDM, drafts N payloads per declared verdict band, invokes `mix corpus.validate` against the running ZenRule agent, diffs actual vs expected ratios, iterates the draft until convergence, and commits the resulting fixture triples under `test/support/upstream/<rule_id>/fixtures/`.
---

# corpus-from-rule

Turn a ZenRule JDM rule into a deterministic test corpus — payloads paired with expected rule-engine responses — verified by running the actual engine and iterating until the response ratio matches the rule's declared bands.

You are the author and the QA. The user names a rule; you draft payloads, run the live engine, read the drift report, iterate, commit on convergence.

## When to use

Trigger whenever the user asks for fixtures rooted in a rule:

- "Build a corpus for de_minimis"
- "Generate test payloads for the new SDN screening rule"
- "Trust-but-verify transaction-screening/<rule_id>"
- "Cover this rule with fixtures"

If they only ask whether a rule is correct, run `mix corpus.validate "<rule_id>/**"` and report — don't loop.

---

## The end-to-end workflow

```
1. READ      → priv/zenrule/<rule_type>/<rule_id>.json + use-cases.md citations
2. CLASSIFY  → onboarding | transaction_screening; expected verdict bands
3. DRAFT     → N payloads per band into test/support/upstream/<rule_id>/fixtures/
4. VALIDATE  → mix corpus.validate "<rule_id>/**" — first run captures responses
5. EXPECT    → for each fixture: commit the captured response as expected.json
                (only after a human eyeball that it matches the band the rule
                 was supposed to produce)
6. ITERATE   → re-run validate; on drift, regenerate the diverging fixtures
                and repeat up to --iter cap (default 5)
7. RECORD    → commit fixtures + a short note in the fixture dir's README.md
```

Steps 1–3 are preparation. Step 4 (and the iterate arm at step 6) is the verified loop — the load-bearing part. Step 5 is the human-in-the-loop checkpoint that turns observed responses into the source of truth.

---

## Step 1 — Read

Open the rule:

```
priv/zenrule/<rule_type>/<rule_id>.json
```

`<rule_type>` is one of `onboarding` or `transaction-screening`. Capture:

- The `inputNode` schema — which fields the payload must populate.
- Every `decisionTableNode` — its inputs, outputs, and rule rows. Each row is a verdict band.
- Any `_description` strings — they often cite the use-case row in `guides/use-cases.md`.

Also read `.claude/skills/zenrule-author/references/payload-schema.md` for the canonical `AtomicFi.RuleEngine.Payload` shape — your drafted payloads must match it.

---

## Step 2 — Classify

Decide:

- **rule_type** — `onboarding` or `transaction_screening`. The directory the rule lives in tells you.
- **Verdict bands** — read the decision-table rows. Each row corresponds to one observable outcome; usually the `transaction.rule` output or an `ledger_accounts.<id>` control. Map each row to one of `PASS | REVIEW | BLOCK | FREEZE` for the `_label.json` regulator-facing label.

For `de_minimis` for example:
- `rule_ach_de_minimis` → PASS (within cap)
- `rule_stablecoin_de_minimis` → PASS (within cap)
- `rule_default` → REVIEW (no rule matched)

Then a transaction *exceeding* a cap is a separate scenario the rule doesn't bake in — that's a fixture you draft, not one read from the rule. Each band needs at least one fixture; ratios are dataset-specific.

---

## Step 3 — Draft

Write fixture triples to `test/support/upstream/<rule_id>/fixtures/<NN>-<slug>/`:

```
01-clean-ach-under-cap/
  payload.json     ← context object POSTed verbatim to ZenRule
  _label.json      ← see schema below
  (expected.json comes from step 5, not here)
```

`_label.json` schema:

```json
{
  "synthetic": true,
  "source": "rule:<rule_id>",
  "rule_type": "transaction_screening",
  "rule_decision": "<rule_id>.json",
  "regime": "aml-cip",
  "cite": "31 CFR §1020.220",
  "verdict": "PASS"
}
```

`payload.json` must:

- match the `AtomicFi.RuleEngine.Payload` schema (see `zenrule-author/references/payload-schema.md`),
- exercise the specific decision-table row this fixture is meant to hit,
- be deterministic — no random UUIDs, no current-timestamps; if a key needs a UUID, use a fixed one tied to the scenario slug.

Aim for: one fixture per band + one decoy near each boundary (e.g. cap+1 unit, cap-1 unit). Decoys catch off-by-one regressions cheaply.

---

## Step 4 — Validate

Bring the engine up if it isn't already:

```sh
make run-backing-services    # starts ZenRule + Watchman + Postgres
```

Then run:

```sh
mix corpus.validate "<rule_id>/**" --out tmp/corpus/<rule_id>-report.md
```

The first run shows every fixture as `🆕 new (no expected.json)` because we haven't committed expectations yet. The report shows the actual response per fixture in collapsible blocks.

If any fixture reports `⚠ engine_error`: the rule rejected the payload shape. Read the error, fix the payload, re-run. Loud failure here is correct.

---

## Step 5 — Expect (human checkpoint)

For each fixture in the report, eyeball the actual response. Two questions:

1. **Does the response match the decision-table row this fixture was meant to hit?** Compare the `transaction.rule` (or LA control) the engine returned against the row's `_id`.
2. **Does the verdict label in `_label.json` correctly describe what the engine did?**

If both answers are yes: commit the captured response as `expected.json` in that fixture's directory. The skill writes one of these formats:

```json
{
  "transaction": {
    "rule": "ach_de_minimis",
    "max_amount": 2500,
    "daily_debit_limit": 10000
    ...
  }
}
```

If either answer is no: the payload was wrong, not the rule. Edit `payload.json` and go back to step 4. **Do not** edit the rule from inside this skill — that is `zenrule-author`'s job.

---

## Step 6 — Iterate

Re-run validate:

```sh
mix corpus.validate "<rule_id>/**"
```

Every fixture should now report `✓ match`. Any `✗ mismatch` means either:

- the rule changed since the last `expected.json` capture (commit the new expected after re-verifying the row mapping), or
- the engine is non-deterministic on some field (most often timestamps; strip them from `expected.json` if so).

The `--iter` cap (default 5) lives in the skill, not the mix task: if five iterations of redrafting + re-validating don't converge, stop and ask the user.

---

## Step 7 — Record

Once all fixtures are `✓ match`:

```
test/support/upstream/<rule_id>/
  README.md                   ← one paragraph: what the rule does, what
                                 the fixtures cover, last-validated date
  fixtures/<NN>-<slug>/
    payload.json
    expected.json
    _label.json
```

Conventional commit, GPG-signed (per CLAUDE.md):

```sh
git commit -S -m "feat(corpus): add fixtures for transaction-screening/<rule_id>"
```

Cross-reference: if the rule maps to a row in `guides/use-cases.md`, add the fixture dir to that row's Test column in the same commit.

---

## Hard requirements

- **No graceful fallbacks.** If `_label.json` is missing or malformed, the mix task crashes loudly. Do not paper over it.
- **Deterministic payloads.** A re-run of the skill on the same rule + seed produces byte-identical fixtures. UUIDs come from `(rule_id, scenario_slug)`, never `Ecto.UUID.generate/0`.
- **Don't edit rules from here.** This skill authors corpus, not rules. Rule edits route through `zenrule-author`.
- **Engine is real.** Mox stubs are for unit tests; this skill talks to the live ZenRule agent at `http://localhost:8090`.

---

## Related

- [zenrule-author](../zenrule-author/SKILL.md) — sister skill, authors the JDM rule files themselves
- [guides/verifying_correctness.md](../../../guides/verifying_correctness.md) — the why and the where of this whole pipeline
- [zenrule-author/references/payload-schema.md](../zenrule-author/references/payload-schema.md) — the canonical `Payload` shape your drafts must match
- [zenrule-author/scripts/evaluate.sh](../zenrule-author/scripts/evaluate.sh) — single-payload curl helper if you need to debug one fixture by hand
