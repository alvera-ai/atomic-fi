# integration-tests

End-to-end vitest suite that exercises the AtomicFi HTTP API against a real Phoenix server + Postgres. Each `tests/<resource>.test.ts` is self-contained: its own `beforeAll` re-authenticates and runs CRUD + 401/404/422/pagination + RLS isolation cases sequentially.

## Run from a clean checkout

```bash
mix ecto.reset && mix ecto.migrate     # rebuild DB + run seed_migrations
mix atomic_fi.dump_bootstrap_creds      # write priv/repo/.bootstrap_creds.json
mix phx.server &                        # starts on :4100
pnpm install
pnpm sdk:build                          # regenerate packages/sdk/generated/
TARGET_ENV=local pnpm --filter atomic-fi-integration-tests test
```

## How it's wired

- **Auth & SDK** come from `@atomic-fi/sdk` (workspace dep). Each spec calls `buildBearerSdk(baseUrl, bearer)` or `buildApiKeySdk(baseUrl, apiKey)` after authenticating.
- **Bootstrap creds** (admin email/password, root api key, platform-admin api key, system tenant slug) live in `priv/repo/.bootstrap_creds.json`, written by `mix atomic_fi.dump_bootstrap_creds`. Read at module-load by `src/env.ts` when `TARGET_ENV=local`. For `hh` / `prod`, `src/env.ts` reads them from environment variables (loaded via `dotenv` from `.env.<TARGET_ENV>`).
- **RLS isolation cases** mint a fresh secondary tenant via `mintSecondaryTenant({ baseUrl, platformAdminApiKey })` from `@atomic-fi/sdk`, then assert that the secondary api key cannot read the primary tenant's row (404).
- `vitest.config.ts` runs files sequentially (`fileParallelism: false`, `singleFork`, alphabetical), so `bootstrap.test.ts` always runs first.

## Coverage

100% endpoint + branch coverage of the OpenAPI surface is the goal — see [issue #15](https://github.com/alvera-ai/atomic-fi/issues/15). One spec per controller; one commit per resource.

| Resource | Controller | Test file | Status |
|---|---|---|---|
| sessions (auth transports) | SessionController | `bootstrap.test.ts` | ✅ partial (verify + 401s) |
| users | UserController | `users.test.ts` | ✅ 10/10 |
| roles | RoleController | `roles.test.ts` | ✅ 11/11 |
| customers | CustomerController | `customers.test.ts` | ✅ 10/10 |
| api_keys | ApiKeyController | `api_keys.test.ts` | ✅ 10/10 |
| tenants | TenantController | `tenants.test.ts` | ✅ 11/11 |
| blocklist_entries | BlocklistEntryController | `blocklist_entries.test.ts` | ✅ 11/11 |
| legal_entities | LegalEntityController | `legal_entities.test.ts` | ✅ 9/10 + 1 it.fails (#17) |
| legal_entity_change_events | LegalEntityChangeEventController | `legal_entity_change_events.test.ts` | ✅ 10/10 |
| beneficial_owners | BeneficialOwnerController | `beneficial_owners.test.ts` | ✅ 10/10 |
| account_holders | AccountHolderController | `account_holders.test.ts` | ✅ 10/10 |
| documents | DocumentController | `documents.test.ts` | ⏳ |
| kyc_requirements | KycRequirementController | `kyc_requirements.test.ts` | ⏳ |
| risk_classifications | RiskClassificationController | `risk_classifications.test.ts` | ⏳ |
| payment_accounts | PaymentAccountController | `payment_accounts.test.ts` | ⏳ |
| ledgers | LedgerController | `ledgers.test.ts` | ⏳ |
| ledger_accounts | LedgerAccountController | `ledger_accounts.test.ts` | ⏳ |
| ledger_entries | LedgerEntryController | `ledger_entries.test.ts` | ⏳ |
| ledger_account_balances | LedgerAccountBalanceController | `ledger_account_balances.test.ts` | ⏳ |
| counterparties | CounterpartyController | `counterparties.test.ts` | ⏳ |
| transactions | TransactionController | `transactions.test.ts` | ⏳ |
| compliance_screenings | ComplianceScreeningController | `compliance_screenings.test.ts` | ⏳ (real Watchman + custom list) |
| account_activity_snapshots | AccountActivitySnapshotController | `account_activity_snapshots.test.ts` | ⏳ |
| party_activity_snapshots | PartyActivitySnapshotController | `party_activity_snapshots.test.ts` | ⏳ |
| sessions (revoke + expired) | SessionController | `sessions.test.ts` | ⏳ |
| info / openapi / docs (meta) | ApiInfoController, OpenApiSpecController, ScalarController | `meta.test.ts` | ⏳ |

Legend: ✅ green · 🚧 in progress · ⏳ pending · ❌ failing/blocked

Per-resource canonical case list (10):

1. `create 201` (with UUID + timestamps in response)
2. `list 200` (and contains the created id)
3. `get 200` (by id)
4. `update 200` (PUT/PATCH)
5. `list pagination` (page + page_size, meta shape)
6. `create invalid 422` (missing required + bad field)
7. `get unknown 404`
8. `unauthorised 401` (no auth + bad auth)
9. `rls: secondary tenant 404` (mintSecondaryTenant; secondary cannot read primary's id)
10. `delete 204 + verify get 404`

Some resources tailor this list (read-only resources skip create/update/delete; compliance_screenings is POST + GET-by-id only with async polling against Watchman; meta endpoints are read-only and unauthenticated where applicable).
