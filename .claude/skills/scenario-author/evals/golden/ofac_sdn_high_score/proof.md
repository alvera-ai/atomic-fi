# corpus.validate report

- corpus: `corpus/zen_rules/ofac_sdn_match`
- transactions: 2

## ofac-txn-01-clean-pass

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404
- scenario: creditor LE clean — Watchman returns 0 matches — should pass

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## ofac-txn-02-putin-block

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 #11
- scenario: creditor LE 'Vladimir Putin' — Watchman returns OFAC SDN match (score >=95) — BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "ofac_sdn_match",
  "status": "rejected"
}
```
</details>


## Summary

| status | count |
|---|---|
| match | 2 |
| new (no _expected) | 0 |
| mismatch | 0 |
| setup_error | 0 |
| engine_error | 0 |
| **total** | **2** |
