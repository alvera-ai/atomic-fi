defmodule PaymentCompliancePlatform.ApiKeyContext.ApiKey do
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.Extensions.Ecto.Encrypted.Binary, as: EncryptedBinary
  alias PaymentCompliancePlatform.TenantContext.Tenant

  @derive {
    Flop.Schema,
    filterable: [:id, :name, :last_used_at, :tenant_id, :customer_id, :role_id],
    sortable: [:id, :name, :last_used_at, :inserted_at, :updated_at],
    default_limit: 20,
    max_limit: 100
  }

  @typedoc """
  Represents an API key for programmatic access with role-based permissions.

  API keys enable secure programmatic access to the system. Each key is associated
  with a tenant and has exactly ONE role. The key_hash field stores an encrypted
  hash of the actual key for secure storage.

  ## Attributes

  * `id` - UUID of the API key
  * `name` - Human-readable name for the API key (e.g., Production App, CI/CD)
  * `key_hash` - Cryptographic hash of the API key for secure storage (encrypted)
  * `last_used_at` - Timestamp of the last successful API request using this key
  * `current_role` - Virtual field for current role (set at runtime during API authentication)
  * `tenant_id` - FK to tenant for multi-tenancy isolation (RLS)
  * `tenant` - Belongs to association with Tenant
  * `customer_id` - Optional FK to customer for customer-scoped API keys (nullable)
  * `customer` - Optional belongs to association with Customer
  * `role_id` - FK to role (API key has ONE role)
  * `role` - Belongs to association with Role
  * `inserted_at` - Timestamp when API key was created
  * `updated_at` - Timestamp when API key was last updated
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  # OpenAPI annotations
  open_api_property(schema: %Schema{type: :string}, key: :name)
  open_api_property(schema: %Schema{type: :string}, key: :key_hash)
  open_api_property(schema: %Schema{type: :string}, key: :last_used_at)

  open_api_schema(
    title: "Api key",
    description: "Api key schema",
    required: [:name, :tenant_id],
    properties: [:id, :name, :key_hash, :last_used_at, :tenant_id, :inserted_at, :updated_at]
  )

  typed_schema "api_keys" do
    field :name, :string
    field :key_hash, :binary
    field :key_value, EncryptedBinary
    field :last_used_at, :utc_datetime_usec

    # Virtual field for current role (set at runtime during API authentication)
    field :current_role, :map, virtual: true

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    # Optional: customer_id for customer-scoped API keys
    belongs_to :customer, PaymentCompliancePlatform.CustomerContext.Customer

    # API key has ONE role (not many-to-many)
    belongs_to :role, PaymentCompliancePlatform.RoleContext.Role

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [
      :name,
      :key_hash,
      :key_value,
      :last_used_at,
      :tenant_id,
      :customer_id,
      :role_id
    ])
    |> validate_required([:name, :key_hash, :key_value, :tenant_id, :role_id])
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:role_id)
  end
end
