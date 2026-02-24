defmodule PaymentCompliancePlatform.LegalEntityContext.LegalEntityPhoneNumber do
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.LegalEntityContext.LegalEntity
  alias PaymentCompliancePlatform.TenantContext.Tenant

  @typedoc """
  Phone number record for a legal entity. Multiple phone numbers per entity are supported.

  ## Attributes

  * `id` - UUID of the phone number record
  * `legal_entity_id` - FK to the parent legal entity
  * `phone_number` - Phone number in E.164 format (e.g., +12125551234)
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

  open_api_property(schema: %Schema{type: :string}, key: :phone_number)

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
    title: "LegalEntityPhoneNumber",
    description: "Phone number record for a legal entity. Stored in E.164 format.",
    required: [:phone_number],
    properties: [
      :id,
      :legal_entity_id,
      :phone_number,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "legal_entity_phone_numbers" do
    field :phone_number, :string

    belongs_to :legal_entity, LegalEntity

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(phone_number, attrs) do
    phone_number
    |> cast(attrs, [:phone_number, :legal_entity_id, :tenant_id])
    |> validate_required([:phone_number, :tenant_id])
    |> foreign_key_constraint(:legal_entity_id)
    |> foreign_key_constraint(:tenant_id)
  end
end
