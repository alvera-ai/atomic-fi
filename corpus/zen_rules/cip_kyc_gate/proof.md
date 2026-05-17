# corpus.validate report

- corpus: `corpus/zen_rules/cip_kyc_gate`
- transactions: 3

## cip-txn-01-approved-pass

- status:   **✓ match**
- regime:   aml-cip
- cite:     BSA §326 (31 CFR §1020.220)
- scenario: sender kyc_status=approved — passes CIP gate

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


## cip-txn-02-in-progress-block

- status:   **✓ match**
- regime:   aml-cip
- cite:     BSA §326 (31 CFR §1020.220) #6
- scenario: sender kyc_status=in_progress — BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "cip_kyc_not_approved",
  "status": "rejected"
}
```
</details>


## cip-txn-03-rejected-block

- status:   **✓ match**
- regime:   aml-cip
- cite:     BSA §326 (31 CFR §1020.220) #7
- scenario: sender kyc_status=rejected — BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "cip_kyc_not_approved",
  "status": "rejected"
}
```
</details>


## Summary

| status | count |
|---|---|
| match | 3 |
| new (no _expected) | 0 |
| mismatch | 0 |
| setup_error | 0 |
| engine_error | 0 |
| **total** | **3** |
