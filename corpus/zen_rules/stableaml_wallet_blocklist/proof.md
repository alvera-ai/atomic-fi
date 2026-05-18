# corpus.validate report

- corpus: `corpus/zen_rules/stableaml_wallet_blocklist`
- transactions: 30

## saw-txn-0000-sanc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: sanctioned wallet 0x47ce0c6ed5b0ce3d3a51fdb1c52dc66a7c3c2936 — BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "stableaml_wallet_blocklist",
  "status": "rejected"
}
```
</details>


## saw-txn-0001-kyc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: recipient kyc=in_progress — de_minimis BLOCK

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


## saw-txn-0002-clean

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: clean wallet + approved kyc — PASS

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


## saw-txn-0003-sanc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: sanctioned wallet 0x3e732383de30e25ab0cafbe05bc3aab0eef86129 — BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "stableaml_wallet_blocklist",
  "status": "rejected"
}
```
</details>


## saw-txn-0004-kyc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: recipient kyc=in_progress — de_minimis BLOCK

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


## saw-txn-0005-clean

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: clean wallet + approved kyc — PASS

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


## saw-txn-0006-sanc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: sanctioned wallet 0x6f1ca141a28907f78ebaa64fb83a9088b02a8352 — BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "stableaml_wallet_blocklist",
  "status": "rejected"
}
```
</details>


## saw-txn-0007-kyc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: recipient kyc=in_progress — de_minimis BLOCK

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


## saw-txn-0008-clean

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: clean wallet + approved kyc — PASS

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


## saw-txn-0009-sanc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: sanctioned wallet 0x0e82e631bfdf5ec6d0389abc56eee40281d98842 — BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "stableaml_wallet_blocklist",
  "status": "rejected"
}
```
</details>


## saw-txn-0010-kyc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: recipient kyc=in_progress — de_minimis BLOCK

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


## saw-txn-0011-clean

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: clean wallet + approved kyc — PASS

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


## saw-txn-0012-sanc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: sanctioned wallet 0x9de910d1f817cfc0d86635903b9ddb787821773f — BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "stableaml_wallet_blocklist",
  "status": "rejected"
}
```
</details>


## saw-txn-0013-kyc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: recipient kyc=in_progress — de_minimis BLOCK

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


## saw-txn-0014-clean

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: clean wallet + approved kyc — PASS

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


## saw-txn-0015-sanc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: sanctioned wallet 0x6566fd32e6440b4268d616479707321851f354df — BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "stableaml_wallet_blocklist",
  "status": "rejected"
}
```
</details>


## saw-txn-0016-kyc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: recipient kyc=in_progress — de_minimis BLOCK

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


## saw-txn-0017-clean

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: clean wallet + approved kyc — PASS

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


## saw-txn-0018-sanc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: sanctioned wallet 0x6e82ab852f0584d61142adc2b5f196a661292e16 — BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "stableaml_wallet_blocklist",
  "status": "rejected"
}
```
</details>


## saw-txn-0019-kyc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: recipient kyc=in_progress — de_minimis BLOCK

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


## saw-txn-0020-clean

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: clean wallet + approved kyc — PASS

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


## saw-txn-0021-sanc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: sanctioned wallet 0x2e2b305cfd35ab22a767b67a8bf5dceb75c8dc7d — BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "stableaml_wallet_blocklist",
  "status": "rejected"
}
```
</details>


## saw-txn-0022-kyc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: recipient kyc=in_progress — de_minimis BLOCK

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


## saw-txn-0023-clean

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: clean wallet + approved kyc — PASS

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


## saw-txn-0024-sanc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: sanctioned wallet 0xd8d2b364ac240297e85c16523ad29b6eb2a56e2b — BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "stableaml_wallet_blocklist",
  "status": "rejected"
}
```
</details>


## saw-txn-0025-kyc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: recipient kyc=in_progress — de_minimis BLOCK

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


## saw-txn-0026-clean

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: clean wallet + approved kyc — PASS

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


## saw-txn-0027-sanc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: sanctioned wallet 0xb78d1edfed9c93d7effd396f95997483f60b869e — BLOCK

<details><summary>response (matches expected)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "stableaml_wallet_blocklist",
  "status": "rejected"
}
```
</details>


## saw-txn-0028-kyc

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: recipient kyc=in_progress — de_minimis BLOCK

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


## saw-txn-0029-clean

- status:   **✓ match**
- regime:   ofac
- cite:     31 CFR §501.404 + GENIUS §4(a)(5)
- scenario: clean wallet + approved kyc — PASS

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
| match | 30 |
| new (no _expected) | 0 |
| mismatch | 0 |
| setup_error | 0 |
| engine_error | 0 |
| **total** | **30** |
