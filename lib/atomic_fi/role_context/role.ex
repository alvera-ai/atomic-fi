defmodule AtomicFi.RoleContext.Role do
  use AtomicFi.Schema

  alias AtomicFi.RoleContext.{
    RoleConstants,
    UserRoleMapping
  }

  alias AtomicFi.TenantContext.Tenant

  @derive {
    Flop.Schema,
    filterable: [:id, :name, :description, :tenant_id],
    sortable: [:id, :name, :description, :inserted_at, :updated_at],
    default_limit: 20,
    max_limit: 100
  }

  @typedoc """
  Represents an authorization role for users and API keys.

  Roles define permissions and access levels within a tenant. Roles can be:
  - Reserved roles (root, platform_admin, system, system_api) — created via migrations only
  - Tenant roles (tenant_admin, user, api) — tenant-scoped

  ## Attributes

  * `id` - UUID of the role
  * `name` - Role name (e.g., admin, member, viewer)
  * `description` - Human-readable description of role purpose and permissions
  * `metadata` - Additional role configuration (permissions, features, limits)
  * `tenant_id` - FK to tenant for multi-tenancy isolation (RLS)
  * `tenant` - Belongs to association with Tenant
  * `users` - Many-to-many association with users via user_role_mappings
  * `api_keys` - One-to-many association with API keys (API keys have single role)
  * `inserted_at` - Timestamp when role was created
  * `updated_at` - Timestamp when role was last updated
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  # OpenAPI annotations
  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)
  open_api_property(schema: %Schema{type: :string}, key: :name)
  open_api_property(schema: %Schema{type: :string}, key: :description)
  open_api_property(schema: %Schema{type: :object, nullable: true}, key: :metadata)
  open_api_property(schema: %Schema{type: :string, format: :uuid}, key: :tenant_id)

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", readOnly: true},
    key: :inserted_at
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", readOnly: true},
    key: :updated_at
  )

  open_api_schema(
    title: "Role",
    description: "Role schema",
    required: [:name, :description, :tenant_id],
    properties: [
      :id,
      :name,
      :description,
      :metadata,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "roles" do
    field :name, :string
    field :description, :string
    field :metadata, :map

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    # Users: many-to-many (users can have multiple roles)
    many_to_many :users, AtomicFi.UserContext.User,
      join_through: UserRoleMapping,
      on_replace: :delete

    # API Keys: one-to-many (API key has ONE role)
    has_many :api_keys, AtomicFi.ApiKeyContext.ApiKey

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :description, :metadata, :tenant_id])
    |> validate_required([:name, :description, :tenant_id])
    |> validate_exclusion(:name, RoleConstants.reserved_roles(),
      message: "is reserved and can only be created via migrations"
    )
    |> unique_constraint(:name, name: :roles_name_tenant_id_index)
  end
end
