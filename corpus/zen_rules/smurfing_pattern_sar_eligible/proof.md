# corpus.validate report

- corpus: `corpus/zen_rules/smurfing_pattern_sar_eligible`
- transactions: 6

## smurf-txn-01

- status:   **✓ match**
- regime:   bsa
- cite:     31 USC §5324
- scenario: 1st of 6 small payments to distinct CPs — below smurf trigger, passes

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


## smurf-txn-02

- status:   **✓ match**
- regime:   bsa
- cite:     31 USC §5324
- scenario: 2nd of 6 small payments to distinct CPs — below smurf trigger, passes

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


## smurf-txn-03

- status:   **✓ match**
- regime:   bsa
- cite:     31 USC §5324
- scenario: 3rd of 6 small payments to distinct CPs — below smurf trigger, passes

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


## smurf-txn-04

- status:   **✓ match**
- regime:   bsa
- cite:     31 USC §5324
- scenario: 4th of 6 small payments to distinct CPs — below smurf trigger, passes

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


## smurf-txn-05

- status:   **✓ match**
- regime:   bsa
- cite:     31 USC §5324
- scenario: 5th of 6 small payments to distinct CPs — below smurf trigger, passes

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


## smurf-txn-06

- status:   **✓ match**
- regime:   bsa
- cite:     31 USC §5324; 31 CFR §1020.320 #20
- scenario: 6th payment — 6 distinct CPs in 24h, total $15,000 > $10,000, all ≤ $3,000 — smurfing BLOCK + SAR-eligible

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "smurfing_pattern_sar_eligible",
  "status": "rejected"
}
```
</details>


## Summary

| status | count |
|---|---|
| match | 6 |
| new (no _expected) | 0 |
| mismatch | 0 |
| setup_error | 0 |
| engine_error | 0 |
| **total** | **6** |
