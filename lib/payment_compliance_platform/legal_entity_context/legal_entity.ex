defmodule PaymentCompliancePlatform.LegalEntityContext.LegalEntity do
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.LegalEntityContext.LegalEntityAddress
  alias PaymentCompliancePlatform.LegalEntityContext.LegalEntityIdentification
  alias PaymentCompliancePlatform.LegalEntityContext.LegalEntityPhoneNumber
  alias PaymentCompliancePlatform.TenantContext.Tenant

  @derive {
    Flop.Schema,
    filterable: [
      :id,
      :tenant_id,
      :legal_entity_type,
      :legal_structure,
      :subject_type,
      :citizenship_country,
      :politically_exposed_person
    ],
    sortable: [
      :id,
      :inserted_at,
      :updated_at,
      :legal_entity_type,
      :last_name,
      :business_name,
      :citizenship_country
    ],
    default_limit: 20,
    max_limit: 100
  }

  @typedoc """
  Shared identity record for individuals and businesses.

  Implements ISO 20022 acmt:007 + FATF CDD. This is a pure identity record —
  domain-specific overlays (risk_rating, kyc_status, account status) belong on
  the domain MDM subject (AccountHolder, etc.).

  ## Attributes

  * `id` - UUID of the legal entity
  * `legal_entity_type` - ISO 20022 entity classification: individual | business
  * `legal_structure` - Legal structure for businesses: corporation | llc | non_profit |
    partnership | sole_proprietorship | trust | government
  * `subject_type` - MDM subject role in payment_risk: account_holder | beneficial_owner
  * `business_name` - Legal registered name of the business
  * `doing_business_as_names` - Array of DBA names
  * `date_formed` - Date of incorporation for business entities
  * `website` - Business website URL
  * `first_name` - Legal first name of the individual
  * `middle_name` - Legal middle name of the individual
  * `last_name` - Legal last name of the individual
  * `prefix` - Name prefix (Mr., Ms., Dr.) — non-PII honorific
  * `suffix` - Name suffix (Jr., Sr., III)
  * `preferred_name` - Preferred or common name
  * `date_of_birth` - Date of birth (FATF CDD requirement)
  * `citizenship_country` - ISO 3166-1 alpha-2 country code (not PII — categorical)
  * `politically_exposed_person` - FATF PEP flag
  * `addresses` - One-to-many addresses
  * `phone_numbers` - One-to-many phone numbers
  * `identifications` - One-to-many identity documents
  * `tenant_id` - FK to tenant for multi-tenancy isolation (RLS)
  * `inserted_at` - Timestamp when record was created
  * `updated_at` - Timestamp when record was last updated
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # OpenAPI annotations
  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{type: :string, enum: ["individual", "business"]},
    key: :legal_entity_type
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: [
        "corporation",
        "llc",
        "non_profit",
        "partnership",
        "sole_proprietorship",
        "trust",
        "government"
      ]
    },
    key: :legal_structure
  )

  open_api_property(
    schema: %Schema{type: :string, nullable: true, enum: ["account_holder", "beneficial_owner"]},
    key: :subject_type
  )

  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :business_name)

  open_api_property(
    schema: %Schema{type: :array, nullable: true, items: %Schema{type: :string}},
    key: :doing_business_as_names
  )

  open_api_property(
    schema: %Schema{type: :string, format: :date, nullable: true},
    key: :date_formed
  )

  open_api_property(schema: %Schema{type: :string, format: :uri, nullable: true}, key: :website)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :first_name)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :middle_name)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :last_name)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :prefix)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :suffix)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :preferred_name)

  open_api_property(
    schema: %Schema{type: :string, format: :date, nullable: true},
    key: :date_of_birth
  )

  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :citizenship_country)

  open_api_property(
    schema: %Schema{type: :boolean, nullable: true},
    key: :politically_exposed_person
  )

  open_api_property(
    schema: %Schema{
      type: :array,
      items: %OpenApiSpex.Reference{"$ref": "#/components/schemas/LegalEntityAddressRequest"}
    },
    key: :addresses
  )

  open_api_property(
    schema: %Schema{
      type: :array,
      items: %OpenApiSpex.Reference{"$ref": "#/components/schemas/LegalEntityPhoneNumberRequest"}
    },
    key: :phone_numbers
  )

  open_api_property(
    schema: %Schema{
      type: :array,
      items: %OpenApiSpex.Reference{
        "$ref": "#/components/schemas/LegalEntityIdentificationRequest"
      }
    },
    key: :identifications
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid},
    key: :tenant_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      readOnly: true,
      description:
        "UUID of the most recent LegalEntityChangeEvent for this entity. " <>
          "Maintained by DB trigger after each change event insert — never written directly."
    },
    key: :latest_change_event_id
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
    title: "LegalEntity",
    description:
      "Shared identity record for individuals and businesses per ISO 20022 acmt:007 + FATF CDD",
    required: [:legal_entity_type, :tenant_id],
    properties: [
      :id,
      :legal_entity_type,
      :legal_structure,
      :subject_type,
      :business_name,
      :doing_business_as_names,
      :date_formed,
      :website,
      :first_name,
      :middle_name,
      :last_name,
      :prefix,
      :suffix,
      :preferred_name,
      :date_of_birth,
      :citizenship_country,
      :politically_exposed_person,
      :addresses,
      :phone_numbers,
      :identifications,
      :tenant_id,
      :latest_change_event_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "legal_entities" do
    # ISO 20022 entity classification
    field :legal_entity_type, Ecto.Enum, values: [:individual, :business]

    field :legal_structure, Ecto.Enum,
      values: [
        :corporation,
        :llc,
        :non_profit,
        :partnership,
        :sole_proprietorship,
        :trust,
        :government
      ]

    # Industry-specific MDM subject role (payment_risk only)
    field :subject_type, Ecto.Enum, values: [:account_holder, :beneficial_owner]

    # Business identity fields
    field :business_name, :string
    field :doing_business_as_names, {:array, :string}, default: []
    field :date_formed, :date
    field :website, :string

    # Individual identity fields (PII)
    field :first_name, :string
    field :middle_name, :string
    field :last_name, :string
    field :prefix, :string
    field :suffix, :string
    field :preferred_name, :string
    field :date_of_birth, :date

    # Non-PII identity fields
    field :citizenship_country, :string
    field :politically_exposed_person, :boolean

    has_many :addresses, LegalEntityAddress, on_replace: :delete
    has_many :phone_numbers, LegalEntityPhoneNumber, on_replace: :delete
    has_many :identifications, LegalEntityIdentification, on_replace: :delete

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    # Trigger-maintained FK to the most recent LegalEntityChangeEvent — never written directly
    field :latest_change_event_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  # Only cast_assoc when the key is present and non-nil in attrs (handles OpenApiSpex nil defaults).
  defp maybe_cast_assoc(changeset, key, attrs, opts) do
    case Map.get(attrs, key) do
      nil -> changeset
      _value -> cast_assoc(changeset, key, opts)
    end
  end

  # Converts an OpenApiSpex struct (or plain map) to a plain atom-keyed map for Ecto.
  defp to_plain_map(attrs) when is_struct(attrs), do: Map.from_struct(attrs)
  defp to_plain_map(attrs) when is_map(attrs), do: attrs

  @doc false
  def changeset(legal_entity, attrs) do
    changeset =
      legal_entity
      |> cast(attrs, [
        :legal_entity_type,
        :legal_structure,
        :subject_type,
        :business_name,
        :doing_business_as_names,
        :date_formed,
        :website,
        :first_name,
        :middle_name,
        :last_name,
        :prefix,
        :suffix,
        :preferred_name,
        :date_of_birth,
        :citizenship_country,
        :politically_exposed_person,
        :tenant_id
      ])
      |> validate_required([:legal_entity_type, :tenant_id])
      |> foreign_key_constraint(:tenant_id)

    tenant_id = get_field(changeset, :tenant_id)

    address_with = fn address, address_attrs ->
      attrs = to_plain_map(address_attrs) |> Map.put(:tenant_id, tenant_id)
      LegalEntityAddress.changeset(address, attrs)
    end

    phone_with = fn phone, phone_attrs ->
      attrs = to_plain_map(phone_attrs) |> Map.put(:tenant_id, tenant_id)
      LegalEntityPhoneNumber.changeset(phone, attrs)
    end

    identification_with = fn identification, identification_attrs ->
      attrs = to_plain_map(identification_attrs) |> Map.put(:tenant_id, tenant_id)
      LegalEntityIdentification.changeset(identification, attrs)
    end

    changeset
    |> maybe_cast_assoc(:addresses, attrs, with: address_with)
    |> maybe_cast_assoc(:phone_numbers, attrs, with: phone_with)
    |> maybe_cast_assoc(:identifications, attrs, with: identification_with)
  end
end
