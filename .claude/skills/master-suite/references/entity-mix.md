# Entity Mix — Existing Catalog Scenarios

The master-suite composes the 10 committed catalog scenarios under `corpus/zen_rules/`. Each scenario is a self-contained NDJSON folder with hand-curated entities and `_expected` verdict blocks.

## The 10 Catalog Scenarios

| Scenario | Entities | Txns | Rule triggered | Trigger mechanism |
|---|---|---|---|---|
| `ofac_sdn_match` | 3 AH, 3 PA | 2 | ofac_sdn_match | Creditor AH named "Vladimir Putin" → Watchman SDN score ≥95 |
| `cip_kyc_gate` | 4 AH, 4 PA | 3 | cip_kyc_not_approved | Sender AH kyc_status=in_progress/rejected |
| `ctr_structuring` | 2 AH, 2 PA | ~10 | ctr_structuring | 3+ sub-$10k debits from same AH in 24h |
| `smurfing_pattern_sar_eligible` | 2 AH, 8+ PA | ~10 | smurfing_pattern_sar_eligible | 6+ small debits to distinct creditor PAs |
| `prohibited_risk_freeze` | 3 AH, 3 PA | 2 | prohibited_risk_freeze | Sender AH risk_level=prohibited |
| `ah_country_kp_residence` | 3 AH, 3 PA | 2 | ah_country_kp_residence | Sender AH citizenship_country=KP + address in DPRK |
| `business_ah_zero_bos` | 3 AH, 3 PA, 1 BO | 2 | business_ah_zero_bos | Business AH with zero beneficial owners |
| `internal_blocklist_lastname` | 3 AH, 3 PA, 1 BL | 2 | internal_blocklist_lastname | Creditor AH last_name matches seeded blocklist |
| `stableaml_wallet_blocklist` | 1 AH, 10 CP, 11 PA | 10 | stableaml_wallet_blocklist | Creditor PA wallet_address on OFAC mixer list |
| `de_minimis_stablecoin` | 3 AH, 4 PA | 3 | stablecoin_block_unverified | Creditor AH kyc_status != approved (P2P transfer) |

## Scale via VU Fan-Out

The `mix corpus.bench` task scales these scenarios via k6-style VU replication:

| VU Level | Total Scenarios | Approx AHs | Approx Txns |
|---|---|---|---|
| 1 | 1 (round-robin) | ~3 | ~5 |
| 10 | 10 (1 of each) | ~30 | ~50 |
| 100 | 100 (10 each) | ~300 | ~500 |
| 1000 | 1000 (100 each) | ~3000 | ~5000 |
| 10000 | 10000 (1000 each) | ~30000 | ~50000 |

Each VU gets a UUID prefix for DB-layer isolation. VUs run in parallel.

## Scale via Synthetic Generators

For larger per-scenario transaction counts:

```bash
# 1000 stableaml transactions
mix corpus.generate.stableaml --emit-corpus --txns 1000 --seed 42

# 10000 SAML-D synthetic rows
mix corpus.generate.saml_d --synthetic --rows 10000 --seed 42 --shards 1 --out tmp/saml-d

# 10000 AMLGentex synthetic rows
mix corpus.generate.amlgentex --synthetic --rows 10000 --seed 42 --shards 1 --out tmp/amlgentex
```

These use `SyntheticSeed` for determinism (same seed → byte-identical NDJSON).

## Architecture

Most transaction-screening rules check `creditor_payment_account.compliance_screenings[]`, populated during entity onboarding (`OnboardingContext.onboard → screen`):

- **Debtor-side rules** (check sender AH properties): cip_kyc_gate, prohibited_risk_freeze, ah_country_kp_residence, business_ah_zero_bos
- **Creditor-side rules** (check creditor PA's screenings): ofac_sdn_match, internal_blocklist_lastname, stableaml_wallet_blocklist, de_minimis_stablecoin
- **Velocity rules** (check sender AH's recent debits): ctr_structuring, smurfing_pattern_sar_eligible
