# corpus.validate report

- corpus: `corpus/zen_rules/ctr_structuring`
- transactions: 3

## ctr-txn-01-first-9500

- status:   **✓ match**
- regime:   bsa-anti-structuring
- cite:     31 USC §5324 / 31 CFR §1020.320 #19
- scenario: 1st sub-CTR debit — 0 prior, passes

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


## ctr-txn-02-second-9500

- status:   **✓ match**
- regime:   bsa-anti-structuring
- cite:     31 USC §5324 / 31 CFR §1020.320 #19
- scenario: 2nd sub-CTR debit — 1 prior, still below structuring threshold

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


## ctr-txn-03-third-9500-block

- status:   **✓ match**
- regime:   bsa-anti-structuring
- cite:     31 USC §5324 / 31 CFR §1020.320 #19
- scenario: 3rd sub-CTR debit inside 24h — structuring pattern — BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ctr_structuring",
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
