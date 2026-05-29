# Correctness Verification — Lotus Probe Questions

After running the `master-suite` skill (100 AH / 1,000 CP / 10,000 Txn), open Lotus at `http://localhost:5173`, log in, get an embed token, and type these questions into the AI dashboard. Download each result as CSV for the compliance bundle.

## Probes

### P1 — Blocked transactions with rejecting rule

> Every BLOCKED transaction with its rejecting rule and regulation cite.

Verifies: all rules that emitted BLOCK verdicts. Cross-reference the `rejected_rule` column against the per-rule summary from `master-suite`.

### P2 — SDN high-score counterparties

> Every counterparty scored ≥95 on Watchman with their SDN list source.

Verifies: `ofac_sdn_match` rule coverage. The count of SDN-matched CPs should align with the ~50 SDN counterparties seeded by `master-suite`.

### P3 — KYC-pending account holders and queued transactions

> Every account holder whose CIP is in progress and the transactions queued behind.

Verifies: `cip_kyc_not_approved` rule. Shows the gate: KYC-pending AHs have their transactions blocked until verification completes.

### P4 — Multi-rule transactions

> Every transaction that hit two or more rules, with both cites.

Verifies: cross-firing behavior. A transaction from a KYC-pending AH to an SDN-matched CP should appear here with both rule cites.

### P5 — Daily blocked-transaction count by scenario

> Daily blocked-transaction count over the seeded period, by scenario.

Verifies: temporal distribution and velocity rules (structuring, smurfing). The blocked count should spike on days where velocity patterns are concentrated.

### P6 — Internal blocklist hits by last name

> Every internal-blocklist hit grouped by last name.

Verifies: `internal_blocklist_lastname` rule. The ~20 blocklist-matching CPs should appear, grouped by the blocklist term that matched.

## Optional probes (use when specific rules fired)

### P7 — Mixer wallet blocks

> Every mixer-wallet counterparty and the transactions blocked against them.

Use when: `stableaml_wallet_blocklist` or `ofac_mixer_usdc` rules fired in the master suite.

### P8 — Smurfing fan-out patterns

> Every SAR-eligible smurfing pattern with the fan-out recipients.

Use when: `smurfing_pattern_sar_eligible` rule fired.

### P9 — Zero-BO business blocks

> Every business account holder with no beneficial owners and their blocked transactions.

Use when: `business_ah_zero_bos` rule fired.

### P10 — Sanctioned-country residence blocks

> Every account holder with DPRK, Iran, Cuba, or Syria residence and their blocked transactions.

Use when: `ah_country_kp_residence` rule fired.

## How to use

1. Run `master-suite --seed 42` (or your chosen seed)
2. Note the per-rule summary and overall rollup printed by the skill
3. Open Lotus: `http://localhost:5173` → Login → Get Embed Token
4. Type each probe question into the Lotus AI input
5. Review the results in the dashboard table
6. Click Export → CSV to download
7. Compare CSV row counts against the per-rule summary numbers
8. Bundle: `master.md` (from `generate-rules`) + Bruno HTML + these CSVs = compliance evidence package
