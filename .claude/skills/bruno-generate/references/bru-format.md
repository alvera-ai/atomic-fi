# Bruno .bru File Format Reference

## File naming

```
001-auth.bru                        — always first, always identical
002-warmup.bru                      — BlocklistCache refresh, always second
003-create-<entity>.bru             — entity creation in FK order
...
0NN-<action>.bru                    — transactions, assertions, lifecycle steps
```

Three-digit zero-padded sequence numbers. Lowercase kebab-case names.

## Standard prelude (001 + 002)

Every scenario folder starts with the same two files:

**001-auth.bru** — `POST {{baseUrl}}/api/sessions` with `{{adminEmail}}`, `{{adminPassword}}`, `{{tenantSlug}}`. Post-response script sets `authBearer` and `tenantId` env vars, resets running ID arrays.

**002-warmup.bru** — `POST {{baseUrl}}/api/tenants/refresh-blocklist-cache` with bearer auth. Ensures BlocklistCache is warm.

Copy these verbatim from an existing scenario (e.g. `ofac-sdn-high-score/001-auth.bru`).

## Entity creation pattern

```bru
script:pre-request {
  bru.setVar("externalId", `SLUG-TYPE-${Date.now()}-${Math.floor(Math.random() * 1e6)}`);
}

body:json {
  {
    "external_id": "{{externalId}}",
    ...fields from ndjson row...
    "tenant_id": "{{tenantId}}"
  }
}

script:post-response {
  bru.setEnvVar("entityId", res.body.id);
}

assert {
  res.status: eq 201
}
```

- Generate unique `external_id` in pre-request script (timestamp + random)
- Capture the server-assigned `id` in post-response for downstream references
- Use env vars to chain IDs between requests (`senderAhId`, `receiverCpId`, `senderPaId`, etc.)

## Transaction assertion pattern

```bru
assert {
  res.status: eq 201
  res.body.status: eq rejected
  res.body.rejected_rule: eq ofac_sdn_match
}
```

Map `_expected` fields directly to assert blocks:
- `status` → `res.body.status: eq <value>`
- `rejected_rule` → `res.body.rejected_rule: eq <value>`
- `rejected_code` → `res.body.rejected_code: eq <value>`
- `null` values: omit from assertions (don't assert `eq null`)

## Docs blocks

Every `.bru` file has a `docs {}` block explaining the step in regulator-walkable English. Include:
- The scenario reference (catalog number if known)
- The regulatory cite from `_label`
- What's expected and why

## Payment account creation

```bru
post {
  url: {{baseUrl}}/api/payment-accounts
  body: json
  auth: bearer
}

body:json {
  {
    "external_id": "{{paExternalId}}",
    "account_holder_id": "{{senderAhId}}",
    "account_type": "wallet",
    "currency": "USD",
    "tenant_id": "{{tenantId}}"
  }
}
```

Note: the API uses `account_holder_id` (the server UUID), not `account_holder_external_id`. This is why entity creation scripts must capture `res.body.id` into env vars.

## Transaction creation

```bru
post {
  url: {{baseUrl}}/api/transactions
  body: json
  auth: bearer
}

body:json {
  {
    "transaction_type": "internal_transfer",
    "amount": 2500,
    "currency": "USD",
    "account_holder_id": "{{senderAhId}}",
    "debtor_payment_account_id": "{{senderPaId}}",
    "creditor_payment_account_id": "{{receiverPaId}}",
    "tenant_id": "{{tenantId}}"
  }
}
```

Note: transaction creation uses server UUIDs (`account_holder_id`, `debtor_payment_account_id`, `creditor_payment_account_id`), not external_ids. The ndjson corpus uses `*_external_id` keys because `mix corpus.validate` resolves them; Bruno must use the server IDs captured from earlier create responses.

## ID chaining: ndjson external_id vs Bruno env vars

The corpus ndjson uses `*_external_id` keys (`account_holder_external_id`, `debtor_external_id`, etc.) because `ScenarioRunner` resolves them to server UUIDs at insert time. Bruno requests must use the resolved server UUIDs from `res.body.id` captured in post-response scripts. Never put ndjson `external_id` values directly into Bruno request bodies for FK references.
