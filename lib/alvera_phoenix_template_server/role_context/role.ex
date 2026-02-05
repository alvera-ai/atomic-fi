defmodule AlveraPhoenixTemplateServer.RoleContext.Role do
  use AlveraPhoenixTemplateServer.Schema

  alias AlveraPhoenixTemplateServer.RoleContext.{
    RoleConstants,
    UserRoleMapping
  }

  alias AlveraPhoenixTemplateServer.TenantContext.Tenant

  @derive {
    Flop.Schema,
    filterable: [:id, :name, :description, :tenant_id, :customer_id],
    sortable: [:id, :name, :description, :inserted_at, :updated_at],
    default_limit: 20,
    max_limit: 100
  }

  @typedoc """
  Represents an authorization role for users and API keys.

  Roles define permissions and access levels within a tenant or customer. Roles can be:
  - Reserved roles (root, platform_admin, system, system_api) - created via migrations only
  - Tenant roles (tenant_admin, user, api) - no customer_id, tenant-scoped
  - Customer roles (customer_admin, employee, customer_api) - with customer_id, customer-scoped

  ## Attributes

  * `id` - UUID of the role
  * `name` - Role name (e.g., admin, member, viewer, employee, customer_admin)
  * `description` - Human-readable description of role purpose and permissions
  * `metadata` - Additional role configuration (permissions, features, limits)
  * `tenant_id` - FK to tenant for multi-tenancy isolation (RLS)
  * `tenant` - Belongs to association with Tenant
  * `customer_id` - Optional FK to customer for customer-scoped roles (nullable)
  * `customer` - Optional belongs to association with Customer
  * `users` - Many-to-many association with users via user_role_mappings
  * `api_keys` - One-to-many association with API keys (API keys have single role)
  * `inserted_at` - Timestamp when role was created
  * `updated_at` - Timestamp when role was last updated
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  # OpenAPI annotations
  open_api_property(schema: %Schema{type: :string}, key: :name)
  open_api_property(schema: %Schema{type: :string}, key: :description)
  open_api_property(schema: %Schema{type: :string}, key: :metadata)

  open_api_schema(
    title: "Role",
    description: "Role schema",
    required: [:name, :tenant_id],
    properties: [:id, :name, :description, :metadata, :tenant_id, :inserted_at, :updated_at]
  )

  typed_schema "roles" do
    field :name, :string
    field :description, :string
    field :metadata, :map

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    # Optional: customer_id for customer-scoped roles (nullable)
    belongs_to :customer, AlveraPhoenixTemplateServer.CustomerContext.Customer

    # Users: many-to-many (users can have multiple roles)
    many_to_many :users, AlveraPhoenixTemplateServer.UserContext.User,
      join_through: UserRoleMapping,
      on_replace: :delete

    # API Keys: one-to-many (API key has ONE role)
    has_many :api_keys, AlveraPhoenixTemplateServer.ApiKeyContext.ApiKey

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :description, :metadata, :tenant_id, :customer_id])
    |> validate_required([:name, :description, :tenant_id])
    |> validate_exclusion(:name, RoleConstants.reserved_roles(),
      message: "is reserved and can only be created via migrations"
    )
    |> validate_customer_role_has_customer_id()
    |> foreign_key_constraint(:customer_id)
    |> unique_constraint(:name, name: :roles_tenant_unique_index)
    |> unique_constraint(:name, name: :roles_customer_unique_index)
  end

  # Validate customer-scoped roles have customer_id
  defp validate_customer_role_has_customer_id(changeset) do
    name = get_field(changeset, :name)
    customer_id = get_field(changeset, :customer_id)

    if RoleConstants.customer_role?(name) and is_nil(customer_id) do
      add_error(changeset, :customer_id, "is required for customer-scoped roles")
    else
      changeset
    end
  end
end
