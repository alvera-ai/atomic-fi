# corpus.validate report

- corpus: `corpus/zen_rules/id_ctr_threshold`
- transactions: 3

## idctr-txn-01-below-pass

- status:   **✓ match**
- regime:   indonesia-aml
- cite:     Law No. 8/2010 Art. 23
- scenario: IDR 499,999,999 — below CTR threshold — should pass

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


## idctr-txn-02-above-block

- status:   **✓ match**
- regime:   indonesia-aml
- cite:     Law No. 8/2010 Art. 23
- scenario: IDR 500,000,000 — at CTR threshold — BLOCK for PPATK filing

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "id_ctr_threshold",
  "status": "rejected"
}
```
</details>


## idctr-txn-03-usd-pass

- status:   **✓ match**
- regime:   indonesia-aml
- cite:     Law No. 8/2010 Art. 23
- scenario: USD 600M — above threshold but wrong currency — should pass (IDR-only rule)

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


## Summary

| status | count |
|---|---|
| match | 3 |
| new (no _expected) | 0 |
| mismatch | 0 |
| setup_error | 0 |
| engine_error | 0 |
| **total** | **3** |
