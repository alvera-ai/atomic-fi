# corpus.validate report

- corpus: `corpus/zen_rules/id_ncj_block`
- transactions: 2

## idncj-txn-01-coop-pass

- status:   **✓ match**
- regime:   indonesia-aml
- cite:     POJK 8/2023 Art. 36
- scenario: creditor counterparty jurisdiction_cooperative=true — should pass

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


## idncj-txn-02-noncoop-block

- status:   **✓ match**
- regime:   indonesia-aml
- cite:     POJK 8/2023 Art. 36
- scenario: creditor counterparty jurisdiction_cooperative=false (FATF black list) — BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "id_ncj_block",
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
