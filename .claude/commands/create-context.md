# Create Ecto Context

Generate an Ecto context with schema, migration, and comprehensive tests.

## Usage

```bash
mix alvera.gen.context <Context> <Schema> <plural> [fields]
```

## Example

```bash
mix alvera.gen.context Accounts User users \
  email:string:unique \
  first_name:string \
  last_name:string \
  phone:string \
  confirmed_at:utc_datetime \
  status:string
```

## Generated Files

- `lib/payment_compliance_platform/<context>/<schema>.ex` - Schema with TypedEctoSchema + OpenAPI annotations
- `lib/payment_compliance_platform/<context>.ex` - Context module with complete CRUD
- `priv/repo/migrations/TIMESTAMP_create_<plural>.exs` - Migration with column comments
- `test/payment_compliance_platform/<context>_test.exs` - Complete tests with @moduletag :refactored
- `test/support/fixtures/<context>_fixtures.ex` - Factory definitions

## Pattern Checklist

### Schema (with TypedEctoSchema + Flop + @typedoc)

```elixir
defmodule PaymentCompliancePlatform.Accounts.User do
  use PaymentCompliancePlatform.Schema  # Includes TypedEctoSchema + ExOpenApiUtils

  # Flop configuration for pagination, filtering, and sorting
  @derive {
    Flop.Schema,
    filterable: [:id, :email, :status, :tenant_id],
    sortable: [:id, :email, :first_name, :last_name, :inserted_at, :updated_at],
    default_limit: 20,
    max_limit: 100
  }

  @typedoc """
  Represents a user account with email authentication and tenant association.

  Users authenticate via email and password. Each user belongs to a tenant and can
  be assigned multiple roles for authorization.

  ## Attributes

  * `id` - UUID of the user
  * `email` - User email address (unique within tenant)
  * `first_name` - User first name
  * `last_name` - User last name
  * `phone` - User phone number
  * `confirmed_at` - Timestamp when user confirmed their email address
  * `status` - User status: active, suspended, deleted
  * `tenant_id` - FK to tenant for multi-tenancy isolation (RLS)
  * `tenant` - Belongs to association with Tenant
  * `inserted_at` - Timestamp when user was created
  * `updated_at` - Timestamp when user was last updated
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # OpenAPI annotations
  open_api_property(schema: %Schema{type: :string, format: :email}, key: :email)
  open_api_property(schema: %Schema{type: :string}, key: :first_name)

  open_api_schema(
    title: "User",
    required: [:email, :tenant_id],
    properties: [:id, :email, :first_name, :last_name, :tenant_id, :inserted_at, :updated_at]
  )

  typed_schema "users" do
    field :email, :string
    field :first_name, :string
    field :last_name, :string
    field :phone, :string
    field :confirmed_at, :utc_datetime
    field :status, :string, default: "active"

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, PaymentCompliancePlatform.TenantContext.Tenant

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :first_name, :last_name, :phone, :confirmed_at, :status, :tenant_id])
    |> validate_required([:email, :tenant_id])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email, name: :users_email_tenant_id_index)
  end
end
```

### Context Module (with Flop + Preloads)

```elixir
defmodule PaymentCompliancePlatform.Accounts do
  import Ecto.Query
  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.Accounts.User

  # Preloads for User responses (defined once, used everywhere)
  @user_preloads [:tenant]

  # List with Flop pagination, filtering, and sorting
  def list_users(user, flop_params \\ %{}) do
    User
    |> preload_query()
    |> Flop.validate_and_run(flop_params,
      for: User,
      repo: Repo,
      query_opts: [user: user]
    )
  end

  # Get with RLS enforcement
  def get_user!(user, id) do
    User
    |> preload_query()
    |> Repo.get!(id, user: user)
  end

  # Create with automatic preloading
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
    |> preload_after_write()
  end

  # Update with automatic preloading
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
    |> preload_after_write()
  end

  # Delete
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  # Changeset for forms
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  # Private: Preload associations for queries (before reads)
  defp preload_query(query) do
    preload(query, ^@user_preloads)
  end

  # Private: Preload associations after writes
  defp preload_after_write({:ok, %User{} = user}) do
    {:ok, Repo.preload(user, @user_preloads, skip_multi_tenancy_check: true)}
  end

  defp preload_after_write({:error, changeset}), do: {:error, changeset}
end
```

### Flop Usage Patterns

Flop provides idiomatic filtering, sorting, and pagination. All filters are defined in the schema via `@derive` and passed through `flop_params`.

**Basic Pagination:**
```elixir
# Get page 1 with 20 items (default)
Accounts.list_users(user, %{page: 1, page_size: 20})
# => {:ok, {[%User{}, ...], %Flop.Meta{current_page: 1, total_count: 100, ...}}}
```

**Sorting:**
```elixir
# Sort by email ascending
Accounts.list_users(user, %{
  order_by: [:email],
  order_directions: [:asc]
})

# Sort by inserted_at descending
Accounts.list_users(user, %{
  order_by: [:inserted_at],
  order_directions: [:desc]
})
```

**Filtering with Operators:**
```elixir
# Filter by exact match
Accounts.list_users(user, %{
  filters: [%{field: :status, op: :==, value: "active"}]
})

# Case-insensitive search (ILIKE)
Accounts.list_users(user, %{
  filters: [%{field: :email, op: :ilike_and, value: "example"}]
})

# Find empty/null values
Accounts.list_users(user, %{
  filters: [%{field: :confirmed_at, op: :empty}]
})

# Combine multiple filters (AND logic)
Accounts.list_users(user, %{
  filters: [
    %{field: :status, op: :==, value: "active"},
    %{field: :email, op: :ilike_and, value: "@company.com"}
  ]
})
```

**Available Filter Operators:**
- `:==`, `:!=` - Exact match/not match
- `:empty`, `:not_empty` - NULL/NOT NULL
- `:>`, `:>=`, `:<`, `:<=` - Comparisons
- `:in`, `:not_in` - List membership
- `:like`, `:ilike` - SQL LIKE (case-sensitive/insensitive)
- `:like_and`, `:ilike_and` - LIKE with AND logic for multiple terms
- `:like_or`, `:ilike_or` - LIKE with OR logic for multiple terms

See full list: https://hexdocs.pm/flop/Flop.Filter.html#t:op/0

**Combined Example:**
```elixir
Accounts.list_users(user, %{
  page: 2,
  page_size: 50,
  order_by: [:inserted_at],
  order_directions: [:desc],
  filters: [
    %{field: :status, op: :==, value: "active"},
    %{field: :email, op: :ilike_and, value: "company"}
  ]
})
```

### Migration (with table and column comments)

**IMPORTANT**: All migrations must include both table comments and column comments. This documentation is visible in the database schema and should match the @typedoc descriptions in schemas.

```elixir
defmodule PaymentCompliancePlatform.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users,
             primary_key: false,
             comment: "User accounts with email authentication and tenant association"
           ) do
      add :id, :binary_id, primary_key: true

      add :email, :string,
        null: false,
        comment: "User email address (unique within tenant)"

      add :first_name, :string,
        comment: "User first name"

      add :last_name, :string,
        comment: "User last name"

      add :phone, :string,
        comment: "User phone number"

      add :confirmed_at, :utc_datetime,
        comment: "Timestamp when user confirmed their email address"

      add :status, :string,
        default: "active",
        null: false,
        comment: "User status: active, suspended, deleted"

      # Multi-tenancy: tenant_id references tenants for RLS
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all),
        null: false,
        comment: "FK to tenant for multi-tenancy isolation (RLS)"

      timestamps(type: :utc_datetime_usec)
    end

    # Composite unique index for multi-tenancy
    create unique_index(:users, [:email, :tenant_id])
    create index(:users, [:tenant_id])
    create index(:users, [:status])
  end
end
```

**Comment Guidelines**:
- **Table comments**: Brief description of what the table stores and its purpose
- **Column comments**: Concise description of each field's purpose
- **Consistency**: Field descriptions in migration comments must match @typedoc descriptions
- **Format**: Use clear, technical language; include allowed values for enums/status fields
- **Multi-line**: Use multi-line format for readability (see examples in existing migrations)

### Tests (with @moduletag :refactored)

```elixir
defmodule PaymentCompliancePlatform.AccountsTest do
  use PaymentCompliancePlatform.DataCase, async: true

  @moduletag :refactored  # For coverage tracking

  alias PaymentCompliancePlatform.Accounts

  describe "list_users/2" do
    test "returns all users for a tenant" do
      tenant = insert(:tenant)
      user1 = insert(:user, owner_id: tenant.id)
      user2 = insert(:user, owner_id: tenant.id)
      _other_tenant_user = insert(:user)  # Different tenant

      users = Accounts.list_users(tenant.id)

      assert length(users) == 2
      assert user1.id in Enum.map(users, & &1.id)
      assert user2.id in Enum.map(users, & &1.id)
    end
  end

  describe "create_user/1" do
    test "creates user with valid attrs" do
      tenant = insert(:tenant)
      attrs = %{
        email: "test@example.com",
        first_name: "John",
        owner_id: tenant.id
      }

      assert {:ok, user} = Accounts.create_user(attrs)
      assert user.email == "test@example.com"
      assert user.first_name == "John"
    end

    test "returns error with invalid attrs" do
      assert {:error, changeset} = Accounts.create_user(%{})
      assert "can't be blank" in errors_on(changeset).email
    end
  end
end
```

## Multi-Tenancy Pattern

All resources MUST include:
- `belongs_to :owner, PaymentCompliancePlatform.TenantContext.Tenant`
- `owner_id` field in schema and migrations
- Composite unique indexes: `unique_index(:table, [:field, :owner_id])`
- Context functions scoped by `owner_id`

## Field Types

| Type | Ecto Type | Example |
|------|-----------|---------|
| string | :string | `name:string` |
| text | :text | `content:text` |
| integer | :integer | `age:integer` |
| float | :float | `rating:float` |
| decimal | :decimal | `price:decimal` |
| boolean | :boolean | `active:boolean` |
| date | :date | `birthdate:date` |
| time | :time | `starts_at:time` |
| datetime | :naive_datetime | `published_at:datetime` |
| utc_datetime | :utc_datetime | `confirmed_at:utc_datetime` |
| uuid | :binary_id | `external_id:uuid` |
| references | references/2 | `user_id:references:users` |
| enum | Ecto.Enum | `status:string` (then add validation) |

## Modifiers

- `:unique` - Adds unique constraint
- `:required` - Adds NOT NULL constraint

Example: `email:string:unique:required`

---

## Post-Generation Checklist

After successfully generating a context, **update the implementation status**:

1. Open [guides/core-modules.md](../../guides/core-modules.md)
2. Update the status table for the new context:
   - Mark Schema as ✅ if migration and schema are complete
   - Mark Docs as ✅ if @typedoc and comments are added
   - Mark Tests as ✅ if tests pass with good coverage
   - Mark RLS as ✅ if tenant_id scoping is implemented
   - Update the Status score (e.g., 4/7)
3. Update the Progress Summary percentages
4. Add a module description in the "Module Descriptions" section

---

## Many-to-Many Relationships (Join Tables)

For many-to-many relationships, use the join table generator:

```bash
mix alvera.gen.join_table <table_name> <Schema1> <Schema2>
```

### Examples

```bash
# User <-> Role many-to-many
mix alvera.gen.join_table user_roles User Role

# ApiKey <-> Role many-to-many
mix alvera.gen.join_table api_roles ApiKey Role
```

### Generated Join Table Pattern

Join tables follow the platform/CRM minimalistic pattern:

```elixir
# Migration
create table(:user_roles, primary_key: false) do
  add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
    null: false,
    primary_key: true

  add :role_id, references(:roles, type: :binary_id, on_delete: :delete_all),
    null: false,
    primary_key: true
end

create index(:user_roles, [:user_id])
create index(:user_roles, [:role_id])
```

### Key Characteristics

- **Composite primary key** - No separate ID field
- **No tenant_id** - Tenant isolation happens through parent entities
- **No timestamps** - Purely minimalistic (opinionated choice)
- **Indexes on FKs** - For query optimization in both directions
- **Cascade delete** - `on_delete: :delete_all` for referential integrity

### Auto-Generated Associations

The generator automatically updates both schemas with `many_to_many` associations:

```elixir
# In User schema
many_to_many :roles, PaymentCompliancePlatform.RoleContext.Role,
  join_through: "user_roles",
  on_replace: :delete

# In Role schema
many_to_many :users, PaymentCompliancePlatform.UserContext.User,
  join_through: "user_roles",
  on_replace: :delete
```

### Usage in Code

```elixir
# Load associations
user = Repo.get(User, id) |> Repo.preload(:roles)

# Add roles to user
user
|> Repo.preload(:roles)
|> Ecto.Changeset.change()
|> Ecto.Changeset.put_assoc(:roles, [role1, role2])
|> Repo.update()

# Query users with specific role
from(u in User,
  join: r in assoc(u, :roles),
  where: r.name == "admin",
  where: u.tenant_id == ^tenant_id
)
|> Repo.all()
```
