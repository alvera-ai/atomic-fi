---
name: fix-failing-tests
description: Systematic workflow to debug and fix failing atomic-fi tests iteratively with `mix test --failed`
when_to_use:
  - Tests failing after changes
  - Systematic test debugging needed
  - Coverage regression or test suite issues
related_commands:
  - /qa:increase-test-coverage (after green, push coverage)
  - /qa:check-api-quality (if a controller / schema test failed)
  - /qa:quality-checks (run before committing — REQUIRED)
---

# Recipe: Fix Failing Tests

Systematic workflow for debugging and fixing failing tests in atomic-fi.
atomic-fi has a single test suite (`mix test`) — no tiered split. Coverage
runs through `mix coveralls`.

**When to use:**
- Tests failing after refactoring or dependency updates
- Random test failures
- New tests failing during development

**Related project conventions:**
- [CLAUDE.md](../../../CLAUDE.md) — testing standards (NO mocks/stubs — use real implementations),
  Controller / Context Contract, OpenAPI Schema Patterns, Multi-Tenancy Pattern
- [coveralls.json](../../../coveralls.json) — coverage skip list + 95% minimum target

---

## §1 The iteration loop — `mix test --failed` is the workflow

This is the canonical loop. Internalise it before reading anything else.

```
  MIX_ENV=test mix ecto.reset       (only if schema drift suspected)
       │
       ▼
  mix test                          ← full run; collect every failure
       │
       ▼
  pick FIRST failure                ← do not skim others; read this one
       │
       ▼
  mix test path/to/that_test.exs:<line>   ← isolated reproduction
       │
       ▼
  diagnose + fix
       │
       ▼
  mix test --failed                 ← re-runs ONLY the previously-failed tests
       │                              elixir reads _build/test/lib/atomic_fi/.mix_test_failures
       ▼
  did the suite shrink?
       │
       ├── yes → pick next first failure, repeat
       │
       └── no → the fix didn't take; back to "diagnose + fix"
```

`--failed` is the key. It persists the failed-test list in `_build/`. Each
iteration runs only that list — as tests turn green, they fall off; as new
regressions appear, they get added. The list shrinks (or grows) on its own;
you never need to track it manually.

**Rules of the loop:**

1. **One test at a time.** Read the FIRST failure's stacktrace + assertion
   diff. Don't open three failures in three tabs. The first failure is
   often the cause of the next two.

2. **Reproduce in isolation before changing anything.** Run
   `mix test path/to/test.exs:<line>` first. If it fails the same way
   solo, you have a clean repro. If it passes solo and fails in the suite,
   skip to §9 — that's a shared-state / order / RLS-leak problem.

3. **Never use `--max-failures`.** atomic-fi's workflow is `--failed`. It
   does the same thing better — it doesn't abort the run, it scopes the
   next run.

4. **Don't widen the fix.** If five tests fail with the same root cause,
   fix the root cause; `--failed` will collapse all five on the next run.
   Don't make five separate edits.

5. **Re-run the FULL suite once at the end.** `--failed` only knows about
   tests that have failed. If your fix broke a previously-passing test,
   `--failed` won't catch it. Final gate is `mix test` (no flags), then
   `mix coveralls`.

---

## §2 When to reset the test database

Only reset if the failure pattern smells like schema drift, sequence reuse
across runs, or RLS rows surviving sandbox rollback:

```bash
MIX_ENV=test mix ecto.reset
```

This drops, recreates, and re-runs every migration under
`priv/repo/migrations/` plus the test-only migrations in
`priv/repo/test_migrations/` (which seed the platform tenant +
`platform_admin_api` API key that `setup_platform_admin_api` expects).

Don't do this on every iteration — it's slow and resets the `--failed` list.

---

## §3 Categorising the first failure

| Symptom | Section |
|---|---|
| `** (KeyError) key :x not found in: %{...}` | §4 schema drift |
| `** (Postgrex.Error) ... violates not-null constraint` | §4 schema drift |
| `** (FunctionClauseError) no function clause matching in <Module>.foo/2` | §5 pattern match |
| `** (RuntimeError) BlocklistCache not initialized for tenant <uuid>` | §6 test setup |
| `Watchman` HTTP error / timeout / connection refused | §6 test setup |
| `Map.from_struct` / `Mapper.to_map` in stacktrace | §7 controller/context contract |
| Assertion fails with `expected: ... got: ...` and the diff is tiny | §8 real bug |
| Assertion fails on `assert_schema(...)` | §8b OpenAPI drift |
| Passes solo, fails in suite | §9 shared state |

---

## §4 Schema drift / migration issues

atomic-fi has one Postgres database (`AtomicFi.Repo`) — no per-domain
datalake repos, no `with_dynamic_repo`. Schemas live under
`lib/atomic_fi/<context>/<resource>.ex`, migrations in
`priv/repo/migrations/`.

```bash
MIX_ENV=test mix ecto.migrations | tail -20
# look for `down` next to a migration the failing test references
```

If a migration is `down`, run `MIX_ENV=test mix ecto.migrate` and re-iterate
with `mix test --failed`.

Verify the live schema matches:
```bash
psql atomic_fi_test -c '\d account_holders'
```

Per [CLAUDE.md § Multi-Tenancy Pattern](../../../CLAUDE.md), every resource
table has a `tenant_id` FK to `tenants` and composite unique indexes on
`[:<field>, :tenant_id]`. Direct `Repo.insert!(..., skip_multi_tenancy_check: true)`
bypasses RLS — acceptable in seed/setup, never for assertions about scoped
visibility.

---

## §5 Pattern match / function clause failures

### 5a. Context expects a request struct, test passed a map

Per [CLAUDE.md § Controller / Context Contract](../../../CLAUDE.md),
contexts pattern-match the typed request struct in the function head:

```elixir
def_with_rls_and_logging create_account_holder(session, %AccountHolderRequest{} = request),
  log_fields: [] do
  # ...
end
```

If a test passes a plain map (`%{holder_type: "individual", ...}`) instead
of `%AccountHolderRequest{...}`, the clause won't match. Construct the
request struct in the test:

```elixir
request = %AtomicFi.OpenApiSchema.AccountHolderRequest{
  holder_type: "individual",
  status: "pending",
  kyc_status: "not_started",
  risk_level: "low",
  enabled_currencies: ["USD"]
}

{:ok, ah} = AccountHolderContext.create_account_holder(session, request)
```

### 5b. Pattern order: struct vs generic map

`%{field: x}` matches BEFORE `%Struct{field: x}` because structs ARE maps.
If you reordered function heads, the struct clause may now be unreachable.
Always put struct-specific clauses FIRST.

---

## §6 Test-environment infrastructure

### 6a. `BlocklistCache not initialized for tenant <uuid>`

The per-tenant ETS table is populated by
`AtomicFi.DecisionContext.BlocklistCache.refresh_tenant_cache/1` (hourly via
Quantum in `:dev` / `:prod`). In `:test`, it's NOT auto-warmed.

Fix in test setup:
```elixir
setup %{tenant: tenant} do
  AtomicFi.DecisionContext.BlocklistCache.refresh_tenant_cache(tenant.id)
  :ok
end
```

### 6b. Watchman timeout / connection refused

The compliance pipeline talks to the real `moov/watchman:v0.61.1` container
— no mocks per testing standards. Bring it up:

```bash
make run-backing-services        # docker compose up — starts upstream watchman
# verify
curl -s http://localhost:8084/ping     # expected: PONG
```

If watchman is up and the test still fails on screening, the issue is in
`AtomicFi.ComplianceScreeningContext`, not the test plumbing.

### 6c. Missing platform tenant / admin API key

ApiKey + Session tests rely on `setup :setup_platform_admin_api` (see
`test/support/conn_case.ex:165`). That setup reads the platform tenant +
`platform_admin_api` role + API key seeded by `priv/repo/test_migrations/`.
If your test bypasses `setup_platform_admin_api`, you must seed manually or
add the setup line to your describe block.

---

## §7 Controller / Context Contract violations

Per [CLAUDE.md](../../../CLAUDE.md), controllers NEVER call
`ExOpenApiUtils.Mapper.to_map/1` or `Map.from_struct/1`. They pass the
typed request struct directly to the context. If a test stacktrace shows
`Mapper.to_map` in a controller frame, the controller is wrong — not the
test.

Quick audit:
```bash
grep -rnE "Map\.from_struct|Mapper\.to_map" lib/atomic_fi_api/controllers/
# Expected: zero hits
```

Fix the controller, then `mix test --failed`.

---

## §8 Real assertion failures vs OpenAPI drift

### §8a. Real bug in code under test

If the test asserts the right invariant and the assertion fails on data
values, the code is wrong — not the test. Common atomic-fi sources:

- **Wrong risk level enum** — `:prohibited` vs `:high` vs `:critical` —
  [guides/use-cases.md](../../../guides/use-cases.md) is the source of
  truth for which scenario maps to which level.
- **RLS scope mismatch** — `def_with_rls_and_logging` scopes queries by
  `session.tenant_id`; if the test session has the wrong tenant_id, you
  get empty results back.
- **Off-by-one in screening logic** — e.g. asserting `kyc_status: :approved`
  but the context returns `:pending` because of a guard clause.

Don't change the test to match buggy behavior. Fix the code.

### §8b. `assert_schema` failures (OpenAPI drift)

Tests using `import OpenApiSpex.TestAssertions` call:
```elixir
assert_schema(json, "AccountHolderResponse", ApiSpec.spec())
```

If this fails:

1. **Schema title mismatch.** Per [CLAUDE.md § OpenAPI Schema Patterns](../../../CLAUDE.md),
   the `open_api_schema(title: "AccountHolder", ...)` title must match the
   auto-generated module name exactly — `"AccountHolder"` ✓,
   `"Account Holder"` (with space) ✗.
2. **Missing `readOnly: true`** on `id`, `inserted_at`, `updated_at`,
   `tenant_id`. They must each have
   `open_api_property(schema: %Schema{... readOnly: true}, ...)` so they're
   excluded from `*Request` and included in `*Response`.
3. **Tag not registered in `ApiSpec`.** `lib/atomic_fi_api/api_spec.ex`
   lists all tags. If your controller's `tags ["Foo"]` doesn't appear
   there, requests pass but the schema lookup fails.

---

## §9 Test passes solo, fails in suite

Almost always one of:

### 9a. RLS leak across tests
A prior test inserted with `skip_multi_tenancy_check: true` and the row
survived Ecto sandbox rollback because the insert went on a parent
connection. Audit direct `Repo.insert!` in factories or setup; prefer
factories that go through changesets.

### 9b. Quantum / Oban firing mid-test
If `:dev`-style Quantum is somehow active in `:test`, the hourly
`BlocklistCache.refresh_tenant_cache` may fire mid-assertion. Verify in
`config/test.exs` that quantum is disabled.

### 9c. ETS state from prior test
`BlocklistCache` lives in ETS keyed by `tenant_id`. Two tests using the
same tenant see each other's state. Either use a fresh tenant per test, or
`BlocklistCache.refresh_tenant_cache(tenant.id)` in setup to reset.

### 9d. `async: true` against a shared resource
Watchman is one container, BlocklistCache is shared ETS. Any test
exercising real screening must be `async: false` on its
`use AtomicFiWeb.ConnCase` / `use AtomicFi.DataCase` line.

---

## §10 Final gate after the `--failed` loop drains

```bash
mix test                       # full run — confirms nothing regressed
mix coveralls 2>&1 | tail -10  # [TOTAL] xx.x% ≥ pre-change baseline
```

If `[TOTAL]` dropped, your fix removed test coverage — add a regression
test for whatever you fixed and re-run.

Then run [/qa:quality-checks](./quality-checks.md) before committing.

---

## Quick reference

```bash
mix test                                              # full run
mix test --failed                                     # iterate on failing subset (the canonical loop)
mix test test/atomic_fi/<path>_test.exs:<line>        # isolated single test
mix test --trace                                      # verbose names + durations (shared-state diagnosis)
mix test --seed 0                                     # disable randomisation (order-dependence diagnosis)
mix coveralls 2>&1 | tail -10                         # coverage gate
MIX_ENV=test mix ecto.reset                           # nuclear DB reset (only when schema drift suspected)
make run-backing-services                             # bring up watchman (docker compose)
curl -s http://localhost:8084/ping                    # watchman smoke
```

Do not use `--max-failures` — `--failed` is the right tool.

---

## Related Commands

- [/qa:increase-test-coverage](./increase-test-coverage.md) — push coverage on a module after green
- [/qa:check-api-quality](./check-api-quality.md) — structural drift checker for controllers
- [/qa:quality-checks](./quality-checks.md) — pre-commit gate (REQUIRED before commit)
- [/qa:review](./review.md) — multi-agent code review for pre-PR
- [/dev:create-rest-api](../dev/create-rest-api.md) — the maker side for new endpoints
