# corpus.validate report

- corpus: `corpus/zen_rules/prohibited_risk_freeze`
- transactions: 2

## pr-txn-01-low-pass

- status:   **✓ match**
- regime:   internal-policy
- cite:     31 CFR §1010.230
- scenario: sender risk_level=low — passes prohibited-risk gate (control)

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


## pr-txn-02-prohibited-block

- status:   **✓ match**
- regime:   internal-policy
- cite:     31 CFR §1010.230 #10
- scenario: sender risk_level=prohibited — FREEZE (modelled as BLOCK)

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "prohibited_risk_freeze",
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
