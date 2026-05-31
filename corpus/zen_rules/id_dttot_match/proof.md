# corpus.validate report

- corpus: `corpus/zen_rules/id_dttot_match`
- transactions: 2

## iddttot-txn-01-clean-pass

- status:   **✓ match**
- regime:   indonesia-aml
- cite:     Law No. 9/2013 Art. 28(1)
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


## iddttot-txn-02-dttot-block

- status:   **✓ match**
- regime:   indonesia-aml
- cite:     Law No. 9/2013 Art. 28(1)
- scenario: creditor LE 'Abdulhai Salek' — Watchman returns DTTOT match — BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "id_dttot_match",
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
