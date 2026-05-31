# Corpus Template

Use these as starting points for country-specific rule corpora. Copy, change the prefix and field values. Every field shown is required — removing any will cause a changeset error.

## account_holders.ndjson

```json
{"external_id": "<PREFIX>-ah-sender", "account_holder_type": "individual", "status": "active", "kyc_status": "approved", "risk_level": "low", "enabled_currencies": ["USD"], "chain_screening": false, "legal_entity": {"legal_entity_type": "individual", "first_name": "Alice", "last_name": "Sender", "citizenship_country": "US", "politically_exposed_person": false, "tenant_id": "TENANT_ID"}, "tenant_id": "TENANT_ID"}
{"external_id": "<PREFIX>-ah-receiver", "account_holder_type": "individual", "status": "active", "kyc_status": "approved", "risk_level": "low", "enabled_currencies": ["USD"], "chain_screening": false, "legal_entity": {"legal_entity_type": "individual", "first_name": "Bob", "last_name": "Receiver", "citizenship_country": "US", "politically_exposed_person": false, "tenant_id": "TENANT_ID"}, "tenant_id": "TENANT_ID"}
```

Notes:
- `tenant_id: "TENANT_ID"` is a placeholder — ScenarioRunner stamps the real tenant_id
- `chain_screening: false` skips Watchman screening (use true only for sanctions rules that need it)
- `account_holder_type` NOT `holder_type`

## counterparties.ndjson (only if the rule checks counterparty fields)

```json
{"external_id": "<PREFIX>-cp-target", "status": "active", "account_holder_external_id": "<PREFIX>-ah-sender", "chain_screening": false, "legal_entity": {"legal_entity_type": "individual", "first_name": "Target", "last_name": "Person", "citizenship_country": "XX", "politically_exposed_person": false, "tenant_id": "TENANT_ID"}, "tenant_id": "TENANT_ID"}
```

## payment_accounts.ndjson

```json
{"external_id": "<PREFIX>-pa-debtor", "account_type": "bank_account", "currency": "USD", "country": "US", "account_holder_external_id": "<PREFIX>-ah-sender", "tenant_id": "TENANT_ID"}
{"external_id": "<PREFIX>-pa-creditor", "account_type": "bank_account", "currency": "USD", "country": "US", "account_holder_external_id": "<PREFIX>-ah-receiver", "tenant_id": "TENANT_ID"}
```

For counterparty-owned PAs (creditor side):
```json
{"external_id": "<PREFIX>-pa-cp-creditor", "account_type": "bank_account", "currency": "USD", "country": "XX", "account_holder_external_id": "<PREFIX>-ah-sender", "counterparty_external_id": "<PREFIX>-cp-target", "tenant_id": "TENANT_ID"}
```

Note: counterparty PAs need BOTH `account_holder_external_id` AND `counterparty_external_id`.

## transactions.ndjson

```json
{"external_id": "<PREFIX>-txn-01-block", "transaction_type": "internal_transfer", "amount": 100000, "currency": "USD", "account_holder_external_id": "<PREFIX>-ah-sender", "debtor_payment_account_external_id": "<PREFIX>-pa-debtor", "creditor_payment_account_external_id": "<PREFIX>-pa-creditor", "_expected": {"status": "rejected", "rejected_rule": "<RULE_SLUG>"}, "_label": {"regime": "<REGIME>", "cite": "<CITE>", "scenario": "<DESCRIPTION>"}, "tenant_id": "TENANT_ID"}
{"external_id": "<PREFIX>-txn-02-pass", "transaction_type": "internal_transfer", "amount": 1000, "currency": "USD", "account_holder_external_id": "<PREFIX>-ah-sender", "debtor_payment_account_external_id": "<PREFIX>-pa-debtor", "creditor_payment_account_external_id": "<PREFIX>-pa-creditor", "_expected": {"status": "accepted"}, "_label": {"regime": "<REGIME>", "cite": "<CITE>", "scenario": "<DESCRIPTION> — control (should pass)"}, "tenant_id": "TENANT_ID"}
```

Notes:
- Use `internal_transfer` not `ach` — avoids `ach_de_minimis` interference
- Always include a positive case (triggers rule) AND a negative case (passes through)
- For counterparty-referencing rules, add `"creditor_counterparty_external_id": "<PREFIX>-cp-target"` to the transaction
- `_expected.rejected_rule` may be semicolon-delimited if multiple rules fire on the same entity (e.g., `"ofac_sdn_match; id_dttot_match"`)
