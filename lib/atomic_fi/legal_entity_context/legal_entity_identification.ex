defmodule AtomicFi.LegalEntityContext.LegalEntityIdentification do
  use AtomicFi.Schema

  alias AtomicFi.LegalEntityContext.LegalEntity
  alias AtomicFi.TenantContext.Tenant

  @typedoc """
  Identity document record for a legal entity per FATF CDD requirements.
  One record per document type per entity (unique on legal_entity_id + id_type).

  ## Attributes

  * `id` - UUID of the identification record
  * `legal_entity_id` - FK to the parent legal entity
  * `id_type` - Document type: us_ssn | us_ein | us_itin | passport |
    driver_license | national_id | lei | tax_id
  * `uri` - Namespace URI for the identifier system (FHIR Identifier.system pattern).
    e.g. urn:oid:2.16.840.1.113883.4.1 for SSN, https://www.gleif.org/lei for LEI
  * `id_number` - The actual identification number (PII)
  * `issuing_country` - ISO 3166-1 alpha-2 country code of the issuing authority
  * `issuing_region` - State or region of the issuing authority
  * `expiration_date` - Expiration date of the identity document
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
      type: :string,
      enum: [
        "us_ssn",
        "us_ein",
        "us_itin",
        "passport",
        "driver_license",
        "national_id",
        "lei",
        "tax_id"
      ]
    },
    key: :id_type
  )

  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :uri)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :id_number)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :issuing_country)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :issuing_region)

  open_api_property(
    schema: %Schema{type: :string, format: :date, nullable: true},
    key: :expiration_date
  )

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
    title: "LegalEntityIdentification",
    description:
      "Identity document for a legal entity per FATF CDD requirements. " <>
        "Unique per (legal_entity_id, id_type).",
    required: [:id_type],
    properties: [
      :id,
      :legal_entity_id,
      :id_type,
      :uri,
      :id_number,
      :issuing_country,
      :issuing_region,
      :expiration_date,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "legal_entity_identifications" do
    field :id_type, Ecto.Enum,
      values: [
        :us_ssn,
        :us_ein,
        :us_itin,
        :passport,
        :driver_license,
        :national_id,
        :lei,
        :tax_id
      ]

    field :uri, :string
    field :id_number, :string
    field :issuing_country, :string
    field :issuing_region, :string
    field :expiration_date, :date

    belongs_to :legal_entity, LegalEntity

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(identification, attrs) do
    identification
    |> cast(attrs, [
      :id_type,
      :uri,
      :id_number,
      :issuing_country,
      :issuing_region,
      :expiration_date,
      :legal_entity_id,
      :tenant_id
    ])
    |> validate_required([:id_type, :tenant_id])
    |> unique_constraint(:id_type,
      name: :legal_entity_identifications_entity_id_type_unique,
      message: "an identification of this type already exists for this legal entity"
    )
    |> foreign_key_constraint(:legal_entity_id)
    |> foreign_key_constraint(:tenant_id)
  end
end
