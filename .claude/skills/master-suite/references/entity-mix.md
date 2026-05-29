# Master Suite Entity Mix

## Account Holders (100)

| Band | Count | Purpose |
|------|-------|---------|
| Clean individuals | ~40 | KYC approved, low risk, US residence. Baseline — transactions should PASS. |
| Clean businesses | ~15 | KYC approved, low risk, with BOs on file. Baseline for business path. |
| KYC-pending individuals | ~10 | `kyc_status: in_progress`. Triggers `cip_kyc_not_approved`. |
| KYC-pending businesses | ~10 | Same but business path. |
| Prohibited risk | ~5 | `risk_level: prohibited`. Triggers `prohibited_risk_freeze`. |
| DPRK/sanctioned country | ~5 | Address in KP/IR/CU/SY. Triggers `ah_country_kp_residence`. |
| Zero-BO businesses | ~5 | Business with no beneficial owners. Triggers `business_ah_zero_bos`. |
| High-risk individuals | ~5 | `risk_level: high`. May trigger risk-based rules. |
| High-risk businesses | ~5 | Same but business path. |

## Counterparties (1,000)

| Band | Count | Purpose |
|------|-------|---------|
| Clean individuals | ~700 | Normal names, no SDN match. Baseline. |
| Clean businesses | ~150 | Normal company names. Baseline. |
| SDN high-score names | ~50 | Names matching moov/watchman SDN entries with score ≥95 (e.g. "Vladimir Putin", "Osama Bin Laden"). Triggers `ofac_sdn_match`. |
| SDN alt-name partials | ~30 | Names partially matching SDN alt-name entries, score 70-94. May trigger REVIEW. |
| Internal blocklist matches | ~20 | Last names matching seeded blocklist entries. Triggers `internal_blocklist_lastname`. |
| Mixer wallet addresses | ~10 | CPs with wallet addresses matching OFAC-sanctioned mixer addresses. Triggers `ofac_mixer_usdc` / `stableaml_wallet_blocklist`. |
| Mixed-risk | ~40 | Various flags that exercise edge cases. |

## Transactions (10,000)

Design transactions to exercise every rule. Mix of:
- Random AH × random CP pairings (most transactions)
- Targeted pairings that fire specific rules:
  - Clean AH → SDN CP = `ofac_sdn_match` fires
  - KYC-pending AH → any CP = `cip_kyc_not_approved` fires
  - Prohibited AH → any CP = `prohibited_risk_freeze` fires
  - Any AH → blocklist CP = `internal_blocklist_lastname` fires
  - Clean AH → mixer CP = `stableaml_wallet_blocklist` fires
  - DPRK AH → any CP = `ah_country_kp_residence` fires
  - Zero-BO business AH → any CP = `business_ah_zero_bos` fires
- Velocity patterns:
  - 3+ sub-$10k debits from same AH in 24h = `ctr_structuring`
  - 6+ small debits from same AH to distinct CPs = `smurfing_pattern_sar_eligible`

**Amounts:** vary realistically. Most $50-$5,000. Some $5,000-$9,999 (structuring band). Some $10,000+ (CTR threshold). Some very small ($1-$50).

**Cross-firing:** deliberate. A transaction from a KYC-pending AH to an SDN-matched CP hits both rules. For `_expected`, use whichever rule fires first per `hitPolicy: "first"`.

## Ndjson output

Write under `tmp/corpus/<seed>/master/`:

```
account_holders.ndjson     (100 lines)
counterparties.ndjson      (1,000 lines)
payment_accounts.ndjson    (at least 1 PA per AH + 1 PA per CP)
transactions.ndjson        (10,000 lines)
blocklist_entries.ndjson   (internal blocklist terms to seed)
```

## Determinism

- Use `:rand.seed(:exsss, {seed, seed * 7919, seed * 6151})` (same pattern as `SyntheticSeed`)
- `external_id` values: `ms-<type>-<zero-padded-index>` (e.g. `ms-ah-001`, `ms-cp-0042`, `ms-txn-00001`)
- Names: draw from fixed arrays, indexed by seed-derived RNG
- Amounts: seed-derived within the appropriate band
