# Plan — 100% E2E coverage of the OpenAPI surface (mirroring `alvera-ai/crm`)

**Branch:** `feat/walkthrough` · **Picked up at:** `f069612`

## Context

A prior session bootstrapped a pnpm workspace at the repo root with `packages/sdk/` (generated from `mix openapi.spec.yaml`) and `integration-tests/` (vitest). One spec exists today: `integration-tests/tests/e2e/bootstrap.test.ts` — 5 cases covering bearer + api-key auth + 401s.

The handover doc the user pasted (`.claude/plans/2026-04-30-e2e-100pct-openapi-coverage-handover.md`) prescribed scaffolding (per-runId state slices, `_order.json`/filename prefixes, `helpers.ts` with `runStandardCrud`, `_template.test.ts.tmpl`, `_coverage.md`) and 18 resource specs. The user has redirected: **mirror `work/alvera-ai/crm` integration tests**, not the platform repo.

The crm shape (verified on disk) is meaningfully simpler:
- Flat `tests/*.test.ts`, `snake_case`, alphabetical execution.
- `vitest.config.ts` sets `fileParallelism: false`; no custom sequencer; no order file.
- `vitest.setup.ts` runs `SandboxService.sandboxReset()` once globally + initial auth.
- Each test file calls `beforeAll` to re-authenticate (its own session), captures resource IDs in `let` vars, runs CRUD + 401/404/422 cases sequentially.
- `client_samples/typescript/<resource>/{create,list,show,update,delete}.ts` doubles as docs samples and test helpers.
- No `helpers.ts`, no `runStandardCrud`, no UUID matchers, no `_template.tmpl`, no `_coverage.md`. Coverage tracked as a table in `README.md`.
- 41 resource specs, ~514 cases, 96.5% status-code coverage. Single tenant; no RLS isolation tests in the integration suite (RLS is asserted in Elixir controller tests).

The user also added one explicit ask not in crm: **secondary-tenant RLS coverage per resource**, with the platform_admin api key produced by a mix task (analogous to a seed script) so it's part of shared bootstrap state.

## Goals & non-goals

**Goal:** atomic-fi `integration-tests/tests/` reaches 100% endpoint + branch coverage of the OpenAPI surface, structured to mirror crm. Each spec is self-contained.

**Out of scope** (per handover):
- 5 use-case specs (`tests/cookbook/`).
- `recordingFetch` / JSONL artifacts for `vitest-to-mdx` / `vitest-to-bruno`.
- Watchman live OFAC fixtures (mock around screening if reached).
- Any cookbook MDX or Bruno generation.

## Decisions (from this session's Q&A)

1. **Platform Admin API key** → mix task produces it as shared state (analogous to a seed migration). Tests read from a known location.
2. **Tenant scoping** → seeded `atomic-fi-tenant` is shared primary; each spec mints a per-runId secondary tenant for its RLS case.
3. **Ordering** → alphabetical, `fileParallelism: false`, no prefixes, no `_order.json`. Bootstrap is `00_…` only insofar as alphabetical order puts it first if needed; otherwise rename to `aa_bootstrap.test.ts` only if a real ordering hazard appears. Default: drop `_order.json`, let alphabetical handle it.
4. **Scope this session** → Phase A scaffolding + as many resource specs as fit, in the dependency order from the handover.

## Phase 0 — GitHub tracking (single feature issue + draft PR)

Before any code lands, create one GitHub feature issue and one draft PR on `alvera-ai/atomic-fi` to track the whole effort. No per-resource sub-issues, no per-scaffolding-step issues — everything lives as a checklist inside the single feature issue, ticked off as commits land.

**Issue:** `feat(integration-tests): 100% E2E OpenAPI coverage (crm-shaped)`
- Body: links to `.claude/plans/handover-100-federated-catmull.md`, plus the Phase A + Phase B checklists below.
- Phase A checklist: mix task, flat layout, vitest setup rewrite, vitest config, mintSecondaryTenant helper, README coverage table.
- Phase B checklist: 20 resources in dependency order — `users`, `roles`, `customers`, `api_keys`, `tenants`, `blocklist_entries`, `legal_entities`, `beneficial_owners`, `account_holders`, `documents`, `kyc_requirements`, `payment_accounts`, `ledgers`, `ledger_accounts`, `ledger_entries`, `ledger_account_balances`, `counterparties`, `transactions`, `compliance_screenings`, `sessions`.

**Draft PR:** opened off `feat/walkthrough` against `main`, title `feat(integration-tests): 100% E2E OpenAPI coverage`, body referencing the issue, marked draft until Phase A merges (or until DoD is met if we ship in one PR).

Each commit on the branch updates the checklist box in the issue body via `gh issue edit` (or just lets the PR commit history speak for itself — pick one).

## Approach — diverge from current scaffolding, converge on crm shape

The current atomic-fi `integration-tests/` has machinery that crm doesn't have and the user no longer wants for resource specs:
- `src/state.ts` (per-runId JSON state slices, `requireBootstrap()`, `vitest-state/`).
- `tests/e2e/_order.json`.
- The `tests/e2e/` subdirectory itself.

**Decision:** keep `bootstrap.test.ts` as a smoke test for auth transports (it works, no reason to rip it out), but **resource specs do not consume its state**. Each resource spec mints its own bearer in `beforeAll` from seeded admin creds (crm pattern). The `state.ts` machinery becomes vestigial for resource specs and can be deleted in a later cleanup commit if it ends up unused.

Test layout becomes flat `integration-tests/tests/<resource>.test.ts` (drop the `e2e/` subdir — crm has no such subdir; either move bootstrap up or leave it where it is and put new specs at the top level). **Recommend moving everything to a flat `tests/` directory** to fully match crm.

### Phase A — Scaffolding (each is its own GPG-signed commit)

**A.1 — Mix task: `mix atomic_fi.dump_bootstrap_creds`**
Produces a gitignored file with the deterministic Root API key + the random Platform Admin API key + admin creds, e.g. `priv/repo/.bootstrap_creds.json`. Reads from the seed-migration-populated DB. Tests load this file at `vitest.setup.ts` time (or fall back to env vars when running against `hh`/`prod`).
- File: `lib/mix/tasks/atomic_fi.dump_bootstrap_creds.ex`
- Output path: `priv/repo/.bootstrap_creds.json` (add to `.gitignore`)
- Fields: `{ tenantSlug, adminEmail, adminPassword, rootApiKey, platformAdminApiKey }`
- **NOTE:** the handover says "don't edit lib/". The user has explicitly approved a mix task here ("we can have a mix script similar to seed exs for it"). Keep the task pure-read against the DB so it can't introduce regressions.

**A.2 — Flat layout migration**
- Move `integration-tests/tests/e2e/bootstrap.test.ts` → `integration-tests/tests/bootstrap.test.ts` (or `aa_bootstrap.test.ts` if alphabetical order needs it).
- Delete `integration-tests/tests/e2e/_order.json`.
- Delete the empty `tests/e2e/` directory.
- Update `vitest.config.ts` `include` glob if needed.

**A.3 — `vitest.setup.ts` global setup (crm-style)**
- Read `priv/repo/.bootstrap_creds.json` (or env overrides).
- Authenticate as admin once, set a default bearer on a shared `OpenAPI`-style config object exported from `src/sdk.ts`.
- No DB reset endpoint exists in atomic-fi (and we're not adding one). Document that callers run `mix ecto.reset && mix ecto.migrate` between local runs to clear data; CI will too.
- Update `src/env.ts` if needed (already maps `TARGET_ENV={local|hh|prod}` correctly).

**A.4 — `vitest.config.ts`: enforce sequential execution**
Confirm/add: `fileParallelism: false`, `testTimeout: 30_000`, `hookTimeout: 30_000`. Currently vitest@2.1.8 — fine.

**A.5 — Optional: `client_samples/` folder**
crm has `client_samples/typescript/<resource>/{create,list,show,update,delete}.ts` — used both as doc snippets and as test helpers via `import { createTenant } from '@atomic-fi/client-samples/tenants/create'`.
- For atomic-fi, **defer** this. Inline the SDK calls inside specs initially; lift to `client_samples/` only when a second consumer appears (e.g. cookbook MDX in next session). Avoids premature abstraction.

**A.6 — RLS helper, minimal**
crm has no RLS tests. atomic-fi adds: a small inline pattern inside each spec's `beforeAll` that mints a secondary tenant via the platform_admin api key, runs one assertion per resource ("secondary tenant cannot GET id created in primary → 404"). Keep it inline; resist the urge to extract `expectRlsIsolation()` until the third spec needs it (then refactor in one commit).

**A.7 — Coverage tracking**
Mirror crm: a single Markdown table in `integration-tests/README.md` with columns `Resource | Endpoints | Status codes documented | Status codes tested | Test file`. Update as specs land. **No `_coverage.md` checklist** (handover artifact, not crm pattern).

### Phase B — Resource specs (one commit per resource, snake_case `.test.ts`)

Order (cheapest → hardest, dependencies first; same as handover):

`users` → `roles` → `customers` → `api_keys` → `tenants` → `blocklist_entries` → `legal_entities` → `beneficial_owners` → `account_holders` → `documents` → `kyc_requirements` → `payment_accounts` → `ledgers` → `ledger_accounts` → `ledger_entries` → `ledger_account_balances` → `counterparties` → `transactions` → `compliance_screenings` → `sessions` (extend bootstrap with revoke + expired bearer cases).

Per spec, the canonical shape (crm-style):

```ts
import { describe, it, expect, beforeAll } from 'vitest'
import { buildBearerSdk } from '../src/sdk'

describe('users', () => {
  let primary: ReturnType<typeof buildBearerSdk>
  let secondary: ReturnType<typeof buildBearerSdk>
  let userId: string

  beforeAll(async () => {
    primary   = await authPrimary()
    secondary = await mintSecondaryTenant()    // uses platform_admin api key
  })

  it('create (201)',      async () => { /* … capture userId */ })
  it('list (200)',        async () => { /* … find userId */ })
  it('get (200)',         async () => { /* … */ })
  it('update (200)',      async () => { /* … */ })
  it('list pagination',   async () => { /* … */ })
  it('create invalid (422)', async () => { /* … */ })
  it('get unknown (404)', async () => { /* … */ })
  it('unauthorised (401)',async () => { /* … */ })
  it('rls: secondary tenant gets 404 for primary id', async () => { /* … */ })
  it('delete (204) + verify get 404', async () => { /* … */ })
})
```

For each resource, port edge cases verbatim from `test/atomic_fi_api/controllers/<resource>_controller_test.exs`. That's the source of truth for fixtures + assertions.

## Files this plan will touch

**Read-only / reference:**
- `lib/atomic_fi_api/controllers/*.ex` (20+ controllers — surface enumeration)
- `test/atomic_fi_api/controllers/*_controller_test.exs` (fixtures + assertions to port)
- `priv/repo/seed_migrations/20260501000001_seed_system_entities.exs:120-128` (api key generation)
- `packages/sdk/spec/openapi.yaml` (regenerate via `mix openapi.spec.yaml --spec AtomicFiApi.ApiSpec`)

**Created / modified:**
- `lib/mix/tasks/atomic_fi.dump_bootstrap_creds.ex` (new)
- `.gitignore` (add `priv/repo/.bootstrap_creds.json`)
- `integration-tests/vitest.setup.ts` (replace per-runId logic with crm-style global auth)
- `integration-tests/vitest.config.ts` (confirm `fileParallelism: false`)
- `integration-tests/tests/bootstrap.test.ts` (moved from `tests/e2e/`)
- `integration-tests/tests/<resource>.test.ts` × 18+ (Phase B)
- `integration-tests/README.md` (coverage table)
- `integration-tests/src/sdk.ts` (extend with `mintSecondaryTenant()` helper using platform_admin api key)

**Deleted:**
- `integration-tests/tests/e2e/_order.json`
- `integration-tests/tests/e2e/` (empty after move)

**Possibly deleted later (not this session):**
- `integration-tests/src/state.ts` per-runId machinery (vestigial after Phase A.3 — leave for now if `bootstrap.test.ts` still uses it)

## Existing utilities to reuse

- `integration-tests/src/sdk.ts` — `buildBearerSdk(bearer)`, `buildApiKeySdk(key)` already exist; extend with `authPrimary()` and `mintSecondaryTenant()` rather than reimplementing.
- `integration-tests/src/env.ts` — `TARGET_ENV` switch already wired.
- `packages/sdk` — typed client + valibot validators already generated; just `import` from `@atomic-fi/sdk`.

## Verification

After Phase A:
```bash
mix ecto.reset && mix ecto.migrate            # rebuilds DB + runs seed_migrations
mix atomic_fi.dump_bootstrap_creds            # writes priv/repo/.bootstrap_creds.json
mix phx.server &                              # starts on :4100
pnpm install
pnpm sdk:build                                # regenerates packages/sdk/generated
TARGET_ENV=local pnpm --filter atomic-fi-integration-tests test
```
Expectations:
- `bootstrap.test.ts`: 5 cases green (unchanged behaviour).
- `users.test.ts` (first resource spec): 10 cases green.
- Each subsequent spec: green on first run, no flakiness across re-runs (run twice in a row to confirm idempotency relative to `mix ecto.reset` cadence).

After Phase B (per resource):
- `TARGET_ENV=local pnpm vitest run tests/<resource>.test.ts` → green.
- `mix phx.routes | grep "/api/<resource>"` cross-check: every endpoint asserted at least once.
- Update `integration-tests/README.md` coverage table; commit `(<resource>: full CRUD + RLS coverage)`.

End-of-session DoD:
- Phase A entirely committed (each piece a separate signed commit).
- At minimum first 5 resource specs green: `users`, `roles`, `customers`, `api_keys`, `tenants`.
- `pnpm test` (no filter) runs fully green from a clean checkout via the verification command sequence above.
- A short follow-up handover at `.claude/plans/handover-100-federated-catmull-followup.md` if remaining specs aren't all done.

## Constraints

- GPG-sign every commit (`git commit -S`). No `Co-Authored-By` trailers.
- One resource = one commit.
- Don't edit `lib/atomic_fi_api/` — surface bugs, don't fix them inline. The new mix task under `lib/mix/tasks/` is the only `lib/` change explicitly authorised this session.
- If `pnpm sdk:build` produces a diff in `packages/sdk/spec/openapi.yaml`, commit it together with the spec(s) that depend on the diff.
- Dev port `:4100`. Phoenix server must be running for any spec to pass; `bootstrap.test.ts` already fails fast with a clear message if not.
