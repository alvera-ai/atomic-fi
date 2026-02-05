defmodule AlveraPhoenixTemplateServer.CustomerContext.Customer do
  use AlveraPhoenixTemplateServer.Schema

  alias AlveraPhoenixTemplateServer.TenantContext.Tenant

  @derive {
    Flop.Schema,
    filterable: [:id, :name, :slug, :status, :tenant_id, :customer_id],
    sortable: [:id, :name, :slug, :inserted_at, :updated_at],
    default_limit: 20,
    max_limit: 100
  }

  @typedoc """
  Represents a customer organization within a tenant.

  Customers are organizations within a tenant that can have their own users and API keys
  through role associations. Users and API keys are linked to customers via roles that
  have a customer_id field.

  ## Attributes

  * `id` - UUID of the customer
  * `name` - Customer organization name
  * `slug` - URL-friendly identifier (unique within tenant)
  * `description` - Customer description
  * `status` - Status: active, inactive, suspended
  * `metadata` - Additional customer configuration
  * `customer_id` - Virtual field aliasing id for RLS (source: :id)
  * `tenant_id` - FK to tenant for multi-tenancy isolation (RLS)
  * `tenant` - Belongs to association with Tenant
  * `roles` - Customer-specific roles (employee, customer_admin, customer_api)
  * `inserted_at` - Timestamp when customer was created
  * `updated_at` - Timestamp when customer was last updated
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # OpenAPI annotations
  open_api_property(schema: %Schema{type: :string}, key: :name)
  open_api_property(schema: %Schema{type: :string}, key: :slug)
  open_api_property(schema: %Schema{type: :string}, key: :description)
  open_api_property(schema: %Schema{type: :string}, key: :status)
  open_api_property(schema: %Schema{type: :string}, key: :metadata)

  open_api_schema(
    title: "Customer",
    description: "Customer organization within a tenant",
    required: [:name, :tenant_id],
    properties: [
      :id,
      :name,
      :slug,
      :description,
      :status,
      :metadata,
      :customer_id,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "customers" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    # Virtual field for RLS (mirrors id)
    field :customer_id, Ecto.UUID, source: :id, autogenerate: false

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    # Customer-specific roles
    has_many :roles, AlveraPhoenixTemplateServer.RoleContext.Role

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(customer, attrs) do
    customer
    |> cast(attrs, [:name, :slug, :description, :status, :metadata, :tenant_id])
    |> validate_required([:name, :tenant_id])
    |> unique_constraint(:slug, name: :customers_slug_tenant_id_index)
    |> foreign_key_constraint(:tenant_id)
  end
end
