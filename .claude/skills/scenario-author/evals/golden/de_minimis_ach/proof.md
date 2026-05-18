# corpus.validate report

- corpus: `corpus/zen_rules/de_minimis_stablecoin`
- transactions: 3

## dms-txn-01-verified-small

- status:   **✓ match**
- regime:   aml-cip
- cite:     31 CFR §1020.220
- scenario: recipient verified, small stablecoin — should pass

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


## dms-txn-02-verified-large

- status:   **✓ match**
- regime:   aml-cip
- cite:     31 CFR §1020.220
- scenario: recipient verified, large stablecoin — should pass (no cap when verified)

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


## dms-txn-03-unverified-block

- status:   **✓ match**
- regime:   aml-cip
- cite:     31 CFR §1020.220
- scenario: recipient unverified, stablecoin — should BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "stablecoin_block_unverified",
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
