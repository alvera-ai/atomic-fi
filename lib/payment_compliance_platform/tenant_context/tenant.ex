defmodule PaymentCompliancePlatform.TenantContext.Tenant do
  use PaymentCompliancePlatform.Schema

  @derive {
    Flop.Schema,
    filterable: [:id, :name, :slug, :status, :tenant_type, :tenant_id],
    sortable: [:id, :name, :slug, :status, :tenant_type, :inserted_at, :updated_at],
    default_limit: 20,
    max_limit: 100
  }

  @typedoc """
  Represents the top-level multi-tenancy entity.

  A Tenant represents an organization or company. Every other entity in the system
  belongs to a tenant directly or indirectly. Each tenant is a separate data partition.

  ## Attributes

  * `id` - UUID of the tenant
  * `name` - Tenant name (organization/company name)
  * `slug` - URL-safe identifier for tenant (e.g., acme-corp)
  * `status` - Lifecycle status: active, suspended, inactive
  * `tenant_type` - Type: platform (root tenant) or standard (user tenant)
  * `metadata` - Tenant-specific configuration and settings
  * `tenant_id` - Virtual field mirroring id for RLS (generated column in database)
  * `inserted_at` - Timestamp when tenant was created
  * `updated_at` - Timestamp when tenant was last updated
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  # OpenAPI annotations
  open_api_property(schema: %Schema{type: :string, format: :uuid}, key: :id)
  open_api_property(schema: %Schema{type: :string}, key: :name)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :slug)

  open_api_property(
    schema: %Schema{type: :string, enum: ["active", "suspended", "inactive"]},
    key: :status
  )

  open_api_property(
    schema: %Schema{type: :string, enum: ["platform", "standard"]},
    key: :tenant_type
  )

  open_api_property(schema: %Schema{type: :object, nullable: true}, key: :metadata)
  open_api_property(schema: %Schema{type: :string, format: :"date-time"}, key: :inserted_at)
  open_api_property(schema: %Schema{type: :string, format: :"date-time"}, key: :updated_at)

  open_api_schema(
    title: "Tenant",
    description: "Tenant schema for multi-tenancy",
    required: [:name, :tenant_type],
    properties: [
      :id,
      :name,
      :slug,
      :status,
      :tenant_type,
      :metadata,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "tenants" do
    field :name, :string
    field :slug, :string
    field :status, Ecto.Enum, values: [:active, :suspended, :inactive]
    field :tenant_type, Ecto.Enum, values: [:platform, :standard]
    field :metadata, :map

    # Multi-tenancy: tenant_id is generated from id for RLS
    # This allows Tenant to participate in RLS queries without self-reference
    field :tenant_id, Ecto.UUID, source: :id, autogenerate: false

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [:name, :slug, :status, :tenant_type, :metadata])
    |> validate_required([:name, :status, :tenant_type])
    |> validate_platform_tenant_creation()
    |> unique_constraint(:slug)
  end

  # Validate platform tenants can only be created via migrations
  defp validate_platform_tenant_creation(changeset) do
    tenant_type = get_field(changeset, :tenant_type)

    # If creating new platform tenant (not updating existing)
    if tenant_type == :platform and changeset.data.__meta__.state == :built do
      add_error(changeset, :tenant_type, "platform tenants can only be created via migrations")
    else
      changeset
    end
  end
end
