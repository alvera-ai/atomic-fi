# corpus.validate report

- corpus: `corpus/zen_rules/internal_blocklist_lastname`
- transactions: 2

## ibl-txn-01-clean-pass

- status:   **✓ match**
- regime:   internal-policy
- cite:     FFIEC BSA/AML Examination Manual — internal lists
- scenario: creditor last_name=Clean — no blocklist hit, passes gate

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


## ibl-txn-02-smurf-block

- status:   **✓ match**
- regime:   internal-policy
- cite:     FFIEC BSA/AML Examination Manual #41
- scenario: creditor last_name=Smurf — internal blocklist hit, BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "internal_blocklist_lastname",
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
