# corpus.validate report

- corpus: `corpus/zen_rules/business_ah_zero_bos`
- transactions: 3

## bz-txn-01-individual-pass

- status:   **✓ match**
- regime:   fincen-cdd
- cite:     31 CFR §1010.380
- scenario: individual sender — out of scope of §1010.380, passes UBO gate

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


## bz-txn-02-business-with-bo-pass

- status:   **✓ match**
- regime:   fincen-cdd
- cite:     31 CFR §1010.380
- scenario: business sender with ≥1 BO disclosed — passes UBO gate

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


## bz-txn-03-business-no-bos-block

- status:   **✓ match**
- regime:   fincen-cdd
- cite:     Corporate Transparency Act; 31 CFR §1010.380 #27
- scenario: business sender with zero BOs — BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "business_ah_zero_bos",
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
