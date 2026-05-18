# corpus.validate report

- corpus: `corpus/zen_rules/ah_country_kp_residence`
- transactions: 2

## kp-txn-01-us-pass

- status:   **✓ match**
- regime:   ofac
- cite:     OFAC E.O. 13466
- scenario: sender country_of_residence=US — passes residency gate (control)

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


## kp-txn-02-kp-block

- status:   **✓ match**
- regime:   ofac
- cite:     OFAC E.O. 13466 #15
- scenario: sender country_of_residence=KP — BLOCK + OFAC report

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ah_country_kp_residence",
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
