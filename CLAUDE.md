# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

**Phoenix Template Server** - A bare-bones Elixir/Phoenix template repository. This is a starting point for new Phoenix projects, unlike the full platform implementation.

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

- NO mocks/stubs - use real implementations
- Prefer integration tests over unit tests
- Fix one test file at a time
- All tests MUST pass before committing

---

## Multi-Tenancy Pattern

### RLS Configuration

Row-Level Security (RLS) fields are configured in `config/config.exs`:

```elixir
config :alvera_phoenix_template_server,
  rls_fields: [:tenant_id],
  rls_primary_field: :tenant_id,
  rls_primary_table: :tenants,
  rls_primary_module: AlveraPhoenixTemplateServer.TenantContext.Tenant
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
   # In lib/alvera_phoenix_template_server/tenant_context/tenant.ex
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

## Template Repository Notice

This is a **template repository**. It provides a minimal Phoenix setup and should be customized for your specific project needs. Unlike the full platform implementation, this template:
- Has minimal dependencies
- No pre-configured resources or domains
- Serves as a clean starting point for new projects
- Should be extended based on project requirements

When using this template, update this CLAUDE.md file with project-specific conventions and patterns as your application grows.
