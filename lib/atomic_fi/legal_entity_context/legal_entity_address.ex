defmodule AtomicFi.LegalEntityContext.LegalEntityAddress do
  use AtomicFi.Schema

  alias AtomicFi.LegalEntityContext.LegalEntity
  alias AtomicFi.TenantContext.Tenant

  @typedoc """
  Address record for a legal entity. Multiple addresses per entity are supported,
  each with one or more address types.

  ## Attributes

  * `id` - UUID of the address
  * `legal_entity_id` - FK to the parent legal entity
  * `address_types` - Types for this address: business | mailing | residential | po_box | other
  * `primary` - Whether this is the primary address for the entity
  * `line1` - Street address line 1
  * `line2` - Street address line 2 (apartment, suite, etc.)
  * `locality` - City or locality
  * `region` - State, province, or region
  * `postal_code` - Postal or ZIP code
  * `country` - ISO 3166-1 alpha-2 country code
  * `tenant_id` - FK to tenant for multi-tenancy isolation (RLS)
  * `inserted_at` - Timestamp when record was created
  * `updated_at` - Timestamp when record was last updated
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # OpenAPI annotations
  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, readOnly: true},
    key: :legal_entity_id
  )

  open_api_property(
    schema: %Schema{
      type: :array,
      items: %Schema{
        type: :string,
        enum: ["business", "mailing", "residential", "po_box", "other"]
      }
    },
    key: :address_types
  )

  open_api_property(schema: %Schema{type: :boolean, nullable: true}, key: :primary)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :line1)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :line2)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :locality)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :region)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :postal_code)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :country)

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, readOnly: true},
    key: :tenant_id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", readOnly: true},
    key: :inserted_at
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", readOnly: true},
    key: :updated_at
  )

  open_api_schema(
    title: "LegalEntityAddress",
    description: "Address record for a legal entity",
    required: [:address_types],
    properties: [
      :id,
      :legal_entity_id,
      :address_types,
      :primary,
      :line1,
      :line2,
      :locality,
      :region,
      :postal_code,
      :country,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "legal_entity_addresses" do
    field :address_types, {:array, :string}, default: []
    field :primary, :boolean, default: false
    field :line1, :string
    field :line2, :string
    field :locality, :string
    field :region, :string
    field :postal_code, :string
    field :country, :string

    belongs_to :legal_entity, LegalEntity

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(address, attrs) do
    address
    |> cast(attrs, [
      :address_types,
      :primary,
      :line1,
      :line2,
      :locality,
      :region,
      :postal_code,
      :country,
      :legal_entity_id,
      :tenant_id
    ])
    |> validate_required([:address_types, :tenant_id])
    |> foreign_key_constraint(:legal_entity_id)
    |> foreign_key_constraint(:tenant_id)
  end
end
