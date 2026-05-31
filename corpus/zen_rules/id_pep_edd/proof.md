# corpus.validate report

- corpus: `corpus/zen_rules/id_pep_edd`
- transactions: 2

## idpep-txn-01-clean-pass

- status:   **✓ match**
- regime:   indonesia-aml
- cite:     POJK 8/2023 + PPATK Reg. 11/2020
- scenario: sender PEP=false — should pass

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


## idpep-txn-02-pep-block

- status:   **✓ match**
- regime:   indonesia-aml
- cite:     POJK 8/2023 + PPATK Reg. 11/2020
- scenario: sender PEP=true — BLOCK for EDD review

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "id_pep_edd",
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
