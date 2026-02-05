# Multi-Tenancy

This guide explains the multi-tenancy architecture used in the Alvera Phoenix Template.

## Overview

The template uses **row-level security (RLS)** via an `owner_id` foreign key for tenant isolation. This is simpler than schema-based or database-per-tenant approaches.

## Architecture

### Tenant Hierarchy

```
Tenant (root entity)
  ├── Users (belongs_to :owner)
  ├── Roles (belongs_to :owner)
  └── [Custom Resources] (belongs_to :owner)
```

Every tenant-scoped resource has an `owner_id` field that references the `tenants` table.

### Database Schema

```sql
-- Root tenant table
CREATE TABLE tenants (
  id UUID PRIMARY KEY,
  name VARCHAR NOT NULL,
  slug VARCHAR NOT NULL UNIQUE,
  status VARCHAR NOT NULL DEFAULT 'active',
  metadata JSONB,
  inserted_at TIMESTAMP,
  updated_at TIMESTAMP
);

-- Example tenant-scoped table
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email VARCHAR NOT NULL,
  -- ... other fields ...

  -- Multi-tenancy: owner_id for RLS
  owner_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  inserted_at TIMESTAMP,
  updated_at TIMESTAMP
);

-- Composite unique index for multi-tenancy
CREATE UNIQUE INDEX users_email_owner_id_index ON users (email, owner_id);
CREATE INDEX users_owner_id_index ON users (owner_id);
```

## Implementation

### 1. Tenant Schema

**File**: `lib/payment_compliance_platform/tenant_context/tenant.ex`

```elixir
defmodule PaymentCompliancePlatform.TenantContext.Tenant do
  use PaymentCompliancePlatform.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  typed_schema "tenants" do
    field :name, :string
    field :slug, :string
    field :status, :string, default: "active"
    field :metadata, :map

    # Associations
    has_many :users, PaymentCompliancePlatform.UserContext.User, foreign_key: :owner_id
    has_many :roles, PaymentCompliancePlatform.RoleContext.Role, foreign_key: :owner_id

    timestamps(type: :utc_datetime)
  end

  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [:name, :slug, :status, :metadata])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
    |> validate_inclusion(:status, ["active", "suspended", "deleted"])
  end
end
```

### 2. Tenant-Scoped Schema

**File**: `lib/payment_compliance_platform/user_context/user.ex`

```elixir
defmodule PaymentCompliancePlatform.UserContext.User do
  use PaymentCompliancePlatform.Schema

  open_api_property(schema: %Schema{type: :string, format: :email}, key: :email)

  open_api_schema(
    title: "User",
    required: [:email, :owner_id],
    properties: [:id, :email, :first_name, :owner_id, :inserted_at, :updated_at]
  )

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  typed_schema "users" do
    field :email, :string
    field :first_name, :string
    field :last_name, :string
    field :status, :string, default: "active"

    # Multi-tenancy: belongs to tenant via owner_id
    belongs_to :owner, PaymentCompliancePlatform.TenantContext.Tenant

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :first_name, :last_name, :status, :owner_id])
    |> validate_required([:email, :owner_id])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email, name: :users_email_owner_id_index)
  end
end
```

**Key points**:
- `belongs_to :owner, Tenant` - Association to tenant
- `owner_id` field - Foreign key to tenants table
- Composite unique constraint - Email unique per tenant

### 3. Tenant-Scoped Context

**File**: `lib/payment_compliance_platform/user_context.ex`

```elixir
defmodule PaymentCompliancePlatform.UserContext do
  import Ecto.Query
  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.UserContext.User

  # List users - ALWAYS scoped by tenant_id
  def list_users(tenant_id, params \\ %{}) do
    User
    |> where(owner_id: ^tenant_id)
    |> Repo.all()
  end

  # Get user - ALWAYS scoped by tenant_id
  def get_user!(id, tenant_id) do
    User
    |> where(id: ^id, owner_id: ^tenant_id)
    |> Repo.one!()
  end

  # Create user - owner_id MUST be provided
  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  # Update user - fetch with tenant_id first
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  # Delete user - fetch with tenant_id first
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end
end
```

**Pattern**:
- All `list_*` and `get_*` functions accept `tenant_id`
- Queries ALWAYS filter by `owner_id`
- Create functions require `owner_id` in attrs
- Update/delete functions assume pre-fetched struct (already scoped)

### 4. Migration

**File**: `priv/repo/migrations/*_create_users.exs`

```elixir
defmodule PaymentCompliancePlatform.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :first_name, :string
      add :last_name, :string
      add :status, :string, default: "active", null: false

      # Multi-tenancy: owner_id references tenants
      add :owner_id, references(:tenants, type: :binary_id, on_delete: :delete_all),
        null: false,
        comment: "Tenant ID for row-level security"

      timestamps(type: :utc_datetime)
    end

    # Composite unique index: email unique per tenant
    create unique_index(:users, [:email, :owner_id])

    # Index for tenant queries
    create index(:users, [:owner_id])

    # Index for status filtering
    create index(:users, [:status])
  end
end
```

**Key points**:
- `owner_id` references `tenants` with `on_delete: :delete_all`
- Composite unique index `[:email, :owner_id]`
- Index on `owner_id` for query performance

## Web Integration

### 1. Assigning Current Tenant

**In authentication plug**:

```elixir
defmodule PaymentCompliancePlatformWeb.Auth do
  def fetch_current_user(conn, _opts) do
    user = get_user_from_session(conn)

    conn
    |> assign(:current_user, user)
    |> assign(:current_tenant_id, user && user.owner_id)
  end
end
```

### 2. LiveView Usage

```elixir
defmodule PaymentCompliancePlatformWeb.UserLive.Index do
  use PaymentCompliancePlatformWeb, :live_view

  on_mount {PaymentCompliancePlatformWeb.UserOnMountHooks, :require_authenticated_user}

  def handle_params(params, _uri, socket) do
    # Get tenant from current user
    tenant_id = socket.assigns.current_user.owner_id

    # Query scoped by tenant
    users = UserContext.list_users(tenant_id, params)

    {:noreply, assign(socket, users: users)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    tenant_id = socket.assigns.current_user.owner_id

    # Get scoped to tenant
    user = UserContext.get_user!(id, tenant_id)
    {:ok, _} = UserContext.delete_user(user)

    {:noreply, socket}
  end
end
```

### 3. API Controller Usage

```elixir
defmodule PaymentCompliancePlatformApi.UserController do
  use PaymentCompliancePlatformWeb, :controller

  def index(conn, params) do
    # Get tenant from authenticated user
    tenant_id = conn.assigns.current_user.owner_id

    users = UserContext.list_users(tenant_id, params)

    render(conn, :index, users: users)
  end

  def create(conn, %{"user" => user_params}) do
    tenant_id = conn.assigns.current_user.owner_id

    # Add tenant to params
    params = Map.put(user_params, "owner_id", tenant_id)

    case UserContext.create_user(params) do
      {:ok, user} ->
        render(conn, :show, user: user)
      {:error, changeset} ->
        render(conn, :errors, changeset: changeset)
    end
  end
end
```

## Data Isolation

### Benefits

1. **Simple**: Single database, simple queries
2. **Performant**: Indexed queries, no middleware overhead
3. **Secure**: SQL-level enforcement via WHERE clauses
4. **Scalable**: Works for thousands of tenants

### Guarantees

- Users cannot access other tenant's data (enforced by context functions)
- Composite unique constraints ensure no cross-tenant conflicts
- CASCADE delete removes all tenant data when tenant deleted

### Limitations

- All tenants share same database (not physically isolated)
- Large tenants may impact small ones (use monitoring)
- Cannot easily export single tenant data (requires WHERE filtering)

## Testing Multi-Tenancy

### Context Tests

```elixir
defmodule PaymentCompliancePlatform.UserContextTest do
  use PaymentCompliancePlatform.DataCase, async: true

  alias PaymentCompliancePlatform.UserContext

  describe "list_users/2" do
    test "returns only users for specified tenant" do
      tenant1 = insert(:tenant)
      tenant2 = insert(:tenant)

      user1 = insert(:user, owner_id: tenant1.id)
      user2 = insert(:user, owner_id: tenant2.id)

      users = UserContext.list_users(tenant1.id)

      assert length(users) == 1
      assert hd(users).id == user1.id
    end
  end

  describe "get_user!/2" do
    test "raises when user belongs to different tenant" do
      tenant1 = insert(:tenant)
      tenant2 = insert(:tenant)

      user = insert(:user, owner_id: tenant1.id)

      assert_raise Ecto.NoResultsError, fn ->
        UserContext.get_user!(user.id, tenant2.id)
      end
    end
  end
end
```

### LiveView Tests

```elixir
defmodule PaymentCompliancePlatformWeb.UserLiveTest do
  use PaymentCompliancePlatformWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "user can only see their tenant's users", %{conn: conn, user: user} do
    # Create user in same tenant
    same_tenant_user = insert(:user, owner_id: user.owner_id)

    # Create user in different tenant
    other_tenant_user = insert(:user)

    {:ok, _view, html} = live(conn, ~p"/admin/users")

    assert html =~ same_tenant_user.email
    refute html =~ other_tenant_user.email
  end
end
```

## Common Patterns

### Pattern 1: Creating Related Resources

```elixir
def create_user_with_role(user_attrs, role_id, tenant_id) do
  # Both user and role must belong to same tenant
  role = RoleContext.get_role!(role_id, tenant_id)

  user_attrs = Map.put(user_attrs, "owner_id", tenant_id)

  Ecto.Multi.new()
  |> Ecto.Multi.insert(:user, User.changeset(%User{}, user_attrs))
  |> Ecto.Multi.run(:user_role, fn _repo, %{user: user} ->
    UserRoleContext.create_user_role(%{
      user_id: user.id,
      role_id: role.id
    })
  end)
  |> Repo.transaction()
end
```

### Pattern 2: Batch Operations

```elixir
def delete_all_inactive_users(tenant_id) do
  User
  |> where(owner_id: ^tenant_id, status: "inactive")
  |> Repo.delete_all()
end
```

### Pattern 3: Cross-Tenant Queries (Admin Only)

```elixir
# Only for system admin operations
def admin_list_all_users do
  User
  |> preload(:owner)
  |> Repo.all()
end
```

## Migration Checklist

When creating a new tenant-scoped resource:

- [ ] Schema includes `belongs_to :owner, Tenant`
- [ ] Migration adds `owner_id` with `references(:tenants)`
- [ ] Migration adds composite unique indexes `[:field, :owner_id]`
- [ ] Migration adds index on `[:owner_id]`
- [ ] Context `list_*` functions accept `tenant_id`
- [ ] Context `get_*` functions accept `tenant_id`
- [ ] Context `create_*` functions require `owner_id` in attrs
- [ ] Tests verify tenant isolation

## Security Considerations

### Defense in Depth

1. **Context Layer**: Always scope queries by `tenant_id`
2. **Database Layer**: Composite unique constraints
3. **Web Layer**: Assign `current_tenant_id` from authenticated user
4. **Test Layer**: Verify isolation in tests

### Common Mistakes

❌ **Forgetting to scope queries**:
```elixir
# BAD: Not scoped by tenant
def get_user!(id) do
  Repo.get!(User, id)
end

# GOOD: Scoped by tenant
def get_user!(id, tenant_id) do
  User
  |> where(id: ^id, owner_id: ^tenant_id)
  |> Repo.one!()
end
```

❌ **Using wrong unique constraint**:
```elixir
# BAD: Email unique globally
create unique_index(:users, [:email])

# GOOD: Email unique per tenant
create unique_index(:users, [:email, :owner_id])
```

❌ **Not validating tenant in create**:
```elixir
# BAD: Allowing arbitrary tenant
def create_user(attrs, _current_user) do
  %User{} |> User.changeset(attrs) |> Repo.insert()
end

# GOOD: Enforcing current user's tenant
def create_user(attrs, current_user) do
  attrs = Map.put(attrs, "owner_id", current_user.owner_id)
  %User{} |> User.changeset(attrs) |> Repo.insert()
end
```

## Next Steps

- [Authentication Guide](authentication.md) - User authentication
- [Testing Guide](testing.md) - Testing tenant isolation
- [Architecture Guide](architecture.md) - Overall system design
