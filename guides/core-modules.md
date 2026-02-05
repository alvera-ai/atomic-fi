# Core Modules

This guide tracks the implementation status and health of each context module in the template.

## Module Status Table

| Context | Schema | Docs | Tests | RLS | API | Vitest | LiveView | Status |
|---------|--------|------|-------|-----|-----|--------|----------|--------|
| TenantContext | ✅ | ✅ | ✅ | N/A | 🔴 | 🔴 | 🔴 | 3/6 |
| UserContext | ✅ | ✅ | ✅ | ✅ | 🔴 | 🔴 | 🔴 | 4/7 |
| CustomerContext | ✅ | ✅ | ✅ | ✅ | 🔴 | 🔴 | 🔴 | 4/7 |
| RoleContext | ✅ | ✅ | ✅ | ✅ | 🔴 | 🔴 | 🔴 | 4/7 |
| ApiKeyContext | ✅ | ✅ | ✅ | ✅ | 🔴 | 🔴 | 🔴 | 4/7 |
| SessionContext | ✅ | ✅ | ✅ | ✅ | 🔴 | 🔴 | 🔴 | 4/7 |

**Legend**:
- ✅ **Complete** - Fully implemented with high quality
- ⚠️ **Partial** - Implemented but needs enhancement
- 🔴 **Not Started** - Not yet implemented
- N/A - Not applicable for this context

## Column Definitions

- **Schema**: Ecto schema and migration with clean nomenclature, table/column comments, proper field types
- **Docs**: Complete @moduledoc, @typedoc with field descriptions, changeset documentation
- **Tests**: 90%+ coverage with comprehensive ExUnit test cases
- **RLS**: Row-level security via tenant_id scoping (N/A for TenantContext which is top-level)
- **API**: REST API endpoints with OpenAPI/Swagger documentation
- **Vitest**: Integration tests using Vitest and TypeScript (testing REST APIs end-to-end)
- **LiveView**: Phoenix LiveView interfaces for web UI
- **Status**: Score showing completed columns out of total applicable columns

## Progress Summary

- **Schema**: 6/6 contexts (100%) - Schemas with migrations, table/column comments
- **Docs**: 6/6 contexts (100%) - Complete @typedoc and field descriptions
- **Tests**: 6/6 contexts (100%) - ExUnit tests with good coverage
- **RLS**: 5/5 contexts (100%) - Row-level security implemented (N/A for Tenant)
- **API**: 0/6 contexts (0%) - REST endpoints not yet implemented
- **Vitest**: 0/6 contexts (0%) - Integration tests not yet implemented
- **LiveView**: 0/6 contexts (0%) - Web UI not yet implemented

## Module Descriptions

### TenantContext

Top-level multi-tenancy entity representing organizations/companies. Each tenant is a separate data partition.

**Purpose**: Foundation for multi-tenancy isolation
**Status**: 3/6 - Core functionality complete, needs API and UI

### UserContext

User accounts with email authentication and tenant association.

**Purpose**: User authentication and authorization
**Status**: 4/7 - Complete with RLS, needs API and UI

### CustomerContext

B2B customer organizations for multi-org tenant structures.

**Purpose**: Manage customer organizations within a tenant. Users and API keys associate with customers through roles.
**Status**: 4/7 - Core functionality complete, needs API and UI
**Pattern Reference**: Similar to MerchantOrg in CRM and Org in Platform

### RoleContext

Authorization roles for users and API keys (e.g., admin, member, viewer).

**Purpose**: Role-based access control (RBAC)
**Status**: 4/7 - Complete with RLS, needs API and UI

### ApiKeyContext

API keys for programmatic access with role-based permissions.

**Purpose**: Machine-to-machine authentication
**Status**: 4/7 - Complete with RLS, needs API and UI

### SessionContext

Active authentication sessions for users and API keys with role-based access.

**Purpose**: Session management and role assumption
**Status**: 4/7 - Complete with RLS, needs API and UI

## Next Steps

1. **Generate REST APIs**: Create OpenAPI-documented REST endpoints for all contexts
2. **Add Integration Tests**: Implement Vitest tests for end-to-end API validation
3. **Implement LiveViews**: Build Phoenix LiveView interfaces for web UI
