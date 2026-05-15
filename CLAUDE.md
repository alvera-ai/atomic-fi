# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

**atomic-fi** — an OSS Phoenix compliance platform for payments. Single-tenant per deployment. Domain primitives: `AccountHolder` (internal payer/payee), `Counterparty` (external party), `LegalEntity` (PII holder), `BeneficialOwner` (FinCEN CDD), plus payment-flow primitives (`Ledger`, `LedgerAccount`, `LedgerEntry`, `Transaction`, `PaymentAccount`). Compliance flows: `AtomicFi.ComplianceScreeningContext` → `AtomicFi.DecisionContext.ScreeningEngine` → external services (Watchman for sanctions, ZenRule for decision logic).

---

## Hard requirements

### No graceful fallbacks, no silent failures

A missing or invalid invariant **must** fail loud. Do not paper over it with a default value, a `_ -> nil`, a rescue that swallows the error, or any other quiet recovery.

- **Banned patterns:**
  - `case Repo.get(...) do %{...} -> ...; nil -> Module.default() end`
  - `case Repo.get(...) do %{...} = x -> x; _ -> %DefaultStruct{} end`
  - `Map.get(map, :key, some_default)` where the key being absent is an invariant violation
  - `try ... rescue _ -> some_default end` around a domain call
  - Defensive `# coveralls-ignore` on a nil/`_` fallback branch — that branch should not exist; delete it instead of ignoring it

- **Required patterns:** `Repo.get!/3`, `Map.fetch!/2`, `Application.fetch_env!/2`, pattern-match only the success shape (`%Tenant{enabled_regimes: r} = repo.get!(...)`), or `raise "<invariant message>"`. Let the process crash; surface the bug.

This applies to every layer — contexts, controllers, workers, schema `prepare_changes`, behaviour impls. The only exception is external transport boundaries (Watchman client, etc.) where the calling domain Behaviour explicitly defines an error case; even there, the **decision** to fall back belongs to the caller, not the transport.

---

## Development Commands

**Testing**
- `mix test` - Run all tests
- `mix test test/path/to/test.exs` - Run specific test file

**Code Quality**
- `mix format` - Format code
- `mix credo --strict` - Code quality analysis

---

## Git Conventions

### Commit Standards

1. **Use conventional commits** (feat, fix, docs, chore, test, refactor)
2. **ALWAYS use `-S` flag** for GPG signing
3. **ALWAYS run tests before committing** - All tests must pass
4. **Run code quality checks before committing:**
   - `mix format --check-formatted`
   - `mix credo --strict`
5. Commit incrementally with clear, descriptive messages

**Example:**
```bash
# Check code quality
mix format
mix credo --strict
mix test

# Commit with GPG signing
git commit -S -m "feat: add user authentication

- Implement JWT token generation
- Add auth plug for protected routes
- Add tests for authentication flow

Fixes #123"
```

### Pre-Commit Checklist

Before every commit, ensure:
- [ ] All tests pass (`mix test`)
- [ ] Code is formatted (`mix format`)
- [ ] No credo warnings (`mix credo --strict`)
- [ ] Commit message follows conventional commits format
- [ ] Commit is GPG signed (`-S` flag)

### Git Flow Workflow

Follow git-flow branching model:
- `main` - Production releases only
- `develop` - Integration branch for next release
- `feature/*` - New features (branch from develop)
- `release/*` - Release preparation (branch from develop, merge to main + develop)
- `hotfix/*` - Production fixes (branch from main, merge to main + develop)

---

## Testing Standards

- Prefer integration tests against real services (Watchman :8084, Postgres, Oban) over unit tests.
- The **one exception**: external HTTP services get a Mox seam at the **domain** layer (e.g. `AtomicFi.DecisionContext.ScreeningEngine.Behaviour`), not the transport layer. `DataCase`/`ConnCase` setup auto-`stub_with`s the real impl, so existing tests still hit the live service; per-test `Mox.expect/3` overrides results without setting up service state.
- Tests fetch domain structs via context getters (`AccountHolderContext.get_account_holder!/2`), never manual `Repo.preload` — context's `@preloads` is the single source of truth.
- Coverage threshold: 90% (`coveralls.json`). External clients (e.g. `Watchman.Client`) use `# coveralls-ignore` on defensive transport/decode branches — treated like a database driver.
- Fix one test file at a time (`mix test --failed`, never `--max-failures`).
- All tests MUST pass before committing.

---

## External Service Boundaries

Pattern for any external HTTP service (Watchman today, ZenRule later):

1. **Plain client** (e.g. `AtomicFi.Watchman.Client`) — uses Req with a small response-step pipeline for decoding. No behaviour on the client itself. Treated like postgres: transport-error and decode-fallback branches use `# coveralls-ignore`.
2. **Domain behaviour** one level up (e.g. `ScreeningEngine.Behaviour`) — callbacks take fully-preloaded domain structs (`%AccountHolder{}`, `%Counterparty{}`, …), not transport-shaped DTOs. The mock seam lives here.
3. **Mox mock** generated via `Mox.defmock(AtomicFi.ScreeningEngineMock, for: ScreeningEngine.Behaviour)` in `test/support/mocks.ex`. Compile-env swap in `config/test.exs`: `config :atomic_fi, :screening_engine, AtomicFi.ScreeningEngineMock`. Callers use `@screening_engine = Application.compile_env(...)`.
4. **DataCase/ConnCase setup hook** calls `Mox.set_mox_from_context(tags)` + `Mox.stub_with(Mock, RealImpl)` so the default behavior is "delegate to real impl".

Reference impls in the platform repo (precedent): `lib/platform/connected_apps/cloudflare_pages_api.ex` (Req + plug-based test seam) and `lib/platform/duck_db_behaviour.ex` (NIF behind a behaviour).

---

## Multi-Tenancy Pattern

### RLS Configuration

Row-Level Security (RLS) fields are configured in `config/config.exs`:

```elixir
config :atomic_fi,
  rls_fields: [:tenant_id],
  rls_primary_field: :tenant_id,
  rls_primary_table: :tenants,
  rls_primary_module: AtomicFi.TenantContext.Tenant
```

### Generators

The `alvera.gen.context` generator automatically adds RLS fields to schemas based on configuration. All generated schemas will include:
- `belongs_to :tenant, Tenant` relationship
- `tenant_id` field in migrations with foreign key constraint
- Composite unique indexes: `[:field, :tenant_id]`
- Context functions scoped by `tenant_id`

### Special Case: Tenant Schema

The **Tenant schema itself** requires special handling since it's the top-level entity:

1. **Generate normally**: `mix alvera.gen.context TenantContext Tenant tenants name:string ...`

2. **Modify the schema** to use a virtual `tenant_id` field that mirrors `id`:
   ```elixir
   # In lib/atomic_fi/tenant_context/tenant.ex
   # Remove: belongs_to :tenant, Tenant

   # Add instead:
   field :tenant_id, Ecto.UUID, source: :id, autogenerate: false
   ```

3. **Modify the migration** to use Postgres GENERATED ALWAYS AS:
   ```elixir
   # In priv/repo/migrations/*_create_tenants.exs
   # Remove: add :tenant_id, references(:tenants, ...)

   # Add instead (after id field):
   execute(
     "ALTER TABLE tenants ADD COLUMN tenant_id UUID GENERATED ALWAYS AS (id) STORED",
     "ALTER TABLE tenants DROP COLUMN tenant_id"
   )
   ```

This pattern ensures that:
- Tenant has a `tenant_id` field that always equals `id`
- RLS queries work consistently across all schemas (including Tenant)
- No circular reference (Tenant referencing itself)

**Inspiration**: This pattern is used in `work/zoca/mononest` and `work/alvera-ai/crm` for consistent multi-tenancy.

---

## OpenAPI Schema Patterns (ExOpenApiUtils)

### Auto-Generated Request/Response Schemas

ExOpenApiUtils automatically generates separate Request and Response schemas from Ecto schemas annotated with `open_api_schema`.

**Naming Convention:**
- Schema title `"AccountHolder"` generates:
  - `AtomicFi.OpenApiSchema.AccountHolderRequest` (for API requests)
  - `AtomicFi.OpenApiSchema.AccountHolderResponse` (for API responses)

**Important:** Title must match module name exactly (no spaces):
- ✅ `title: "AccountHolder"`
- ❌ `title: "Account holder"` (space breaks auto-generation)

### ReadOnly vs WriteOnly Fields

**ReadOnly fields** (`readOnly: true`):
- Appear ONLY in Response schemas
- Excluded from Request schemas
- Use for server-generated values: `id`, `inserted_at`, `updated_at`, `tenant_id`

```elixir
open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)
open_api_property(schema: %Schema{type: :string, format: :"date-time", readOnly: true}, key: :inserted_at)
open_api_property(schema: %Schema{type: :string, format: :"date-time", readOnly: true}, key: :updated_at)
```

**WriteOnly fields** (`writeOnly: true`):
- Appear ONLY in Request schemas
- Excluded from Response schemas
- Use for sensitive input: passwords, tokens

```elixir
open_api_property(schema: %Schema{type: :string, writeOnly: true}, key: :password)
```

**No flag:**
- Appears in BOTH Request and Response schemas
- Use for regular data fields

```elixir
open_api_property(schema: %Schema{type: :string}, key: :name)
```

### Nested Schema References

For embedded schemas in arrays, reference the auto-generated Request/Response variants:

```elixir
# In parent schema (AccountHolder)
open_api_property(
  schema: %Schema{
    type: :array,
    items: %OpenApiSpex.Reference{"$ref": "#/components/schemas/InterestedCompanyRequest"}
  },
  key: :interested_companies
)
```

The nested schema (InterestedCompany) must also have proper `open_api_schema` annotation:

```elixir
# In InterestedCompany embedded schema
open_api_schema(
  title: "InterestedCompany",  # Generates InterestedCompanyRequest/Response
  description: "Interested company for account holder screening",
  required: [:name],
  properties: [:name, :created, :dissolved]
)
```

### Reference
- GitHub: https://github.com/v3-dot-cash/ex_open_api_utils

---

## Controller / Context Contract

### No massaging in controllers — pass typed structs directly

Controllers **NEVER** call `ExOpenApiUtils.Mapper.to_map/1` or perform any attribute
conversion. They pass the typed OpenApiSpex struct directly to the context function:

```elixir
# ✅ Correct — pass the struct directly
AccountHolderContext.create_account_holder(session, account_holder_request)
AccountHolderContext.update_account_holder(session, account_holder, account_holder_request)

# ❌ Wrong — no Mapper.to_map in controllers
attrs = ExOpenApiUtils.Mapper.to_map(account_holder_request)
AccountHolderContext.create_account_holder(session, attrs)
```

### Context functions own the struct conversion

`use AtomicFi.Schema` → `use ExOpenApiUtils` replaces `Ecto.Changeset.cast/3`
with `ExOpenApiUtils.Changeset.cast/3`, which calls `Mapper.to_map(params)` internally.
This means **the struct can be passed directly to `changeset/2`** — no manual conversion needed.

Context functions:
- Pattern-match on the typed struct in the function head: `%AccountHolderRequest{} = request`
- Pass the struct directly to `changeset/2` — `ExOpenApiUtils.Changeset.cast` handles conversion
- Read struct fields directly — `request.chain_screening`, NOT `Map.get(attrs, :chain_screening)`
- Test structs must set all fields explicitly (full replacement, no partial updates)

```elixir
# ✅ Correct context signature — struct passed directly, Mapper.to_map called inside cast
def_with_rls_and_logging create_account_holder(session, %AccountHolderRequest{} = request), log_fields: [] do
  with {:ok, account_holder} <-
         %AccountHolder{}
         |> AccountHolder.changeset(request)
         |> Repo.insert(session: session) do
    if request.chain_screening do
      # enqueue Oban job
    end
    {:ok, account_holder}
  end
end

# ❌ Wrong — Map.from_struct bypasses Mapper protocol and includes all nil fields
AccountHolder.changeset(account_holder, Map.from_struct(request))
```

### Side effects belong in the context layer

Background jobs (Oban) and other side effects are enqueued inside context functions —
not in controllers. Controllers are dumb: call context, render response.

---

