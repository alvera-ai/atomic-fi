defmodule AtomicFi.LegalEntityContext.LegalEntity do
  use AtomicFi.Schema

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.BeneficialOwnerContext.BeneficialOwner
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.LegalEntityContext.LegalEntityAddress
  alias AtomicFi.LegalEntityContext.LegalEntityIdentification
  alias AtomicFi.LegalEntityContext.LegalEntityPhoneNumber
  alias AtomicFi.TenantContext.Tenant

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
  * `subject_type` - MDM subject role in payment_risk:
    `account_holder` | `counterparty` | `account_holder_beneficial_owner`
    | `counterparty_beneficial_owner`. The two BO variants disambiguate
    whether the BO is a UBO of the host AccountHolder or of a
    Counterparty under that AH; the parent-FK presence is enforced by
    the `legal_entities_subject_fk_consistency` CHECK constraint.
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
    schema: %Schema{
      type: :string,
      nullable: true,
      readOnly: true,
      enum: [
        "account_holder",
        "counterparty",
        "account_holder_beneficial_owner",
        "counterparty_beneficial_owner"
      ]
    },
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
      type: :string,
      nullable: true,
      enum: ["bank", "msb", "broker_dealer", "insurance", "fintech", "none"],
      description:
        "Financial institution classification — set by compliance analyst " <>
          "during KYB, not by the API consumer. Used by §5318(i)/(j) rules."
    },
    key: :institution_type
  )

  open_api_property(
    schema: %Schema{
      type: :boolean,
      nullable: true,
      description:
        "Does the institution maintain a physical office? false = shell bank. " <>
          "Set by compliance analyst from correspondent banking questionnaire. " <>
          "Used by §5318(j) foreign shell bank prohibition."
    },
    key: :has_physical_presence
  )

  open_api_property(
    schema: %Schema{
      type: :boolean,
      nullable: true,
      description:
        "Does the entity's home jurisdiction cooperate with US AML enforcement? " <>
          "Set by compliance analyst from FATF grey/black list status. " <>
          "Used by §5318(i) enhanced due diligence for non-cooperative jurisdictions."
    },
    key: :jurisdiction_cooperative
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
    schema: %Schema{type: :string, readOnly: true},
    key: :legal_entity_number
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
      :legal_entity_number,
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

    # MDM subject role discriminator. Set by the per-parent named changeset
    # (account_holder_changeset / counterparty_changeset / beneficial_owner_changeset)
    # via put_change — never cast from caller attrs.
    field :subject_type, Ecto.Enum,
      values: [
        :account_holder,
        :counterparty,
        :account_holder_beneficial_owner,
        :counterparty_beneficial_owner
      ]

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

    # Institutional due diligence fields — populated by the compliance team
    # during KYB (Know Your Business) or correspondent banking onboarding,
    # NOT by the API consumer or the counterparty themselves.

    # §5318(i)/(j): What kind of financial institution is this entity?
    # Compliance analyst sets this after reviewing incorporation docs.
    field :institution_type, Ecto.Enum,
      values: [:bank, :msb, :broker_dealer, :insurance, :fintech, :none]

    # §5318(j): Does the institution maintain a physical office in any
    # country? false = shell bank. Compliance analyst determines this
    # from correspondent banking questionnaire or FATF mutual evaluation.
    field :has_physical_presence, :boolean

    # §5318(i): Does the entity's home jurisdiction cooperate with US AML
    # enforcement? Compliance analyst sets this from FATF grey/black list
    # status or bilateral treaty review.
    field :jurisdiction_cooperative, :boolean

    has_many :addresses, LegalEntityAddress, on_replace: :delete
    has_many :phone_numbers, LegalEntityPhoneNumber, on_replace: :delete
    has_many :identifications, LegalEntityIdentification, on_replace: :delete

    # Parent FKs — at most one of `counterparty_id` / `beneficial_owner_id` is
    # set per row (selected by `subject_type`). `account_holder_id` is NOT NULL
    # on every row: for AH-owned LEs it's the AH itself; for CP-owned and
    # BO-owned LEs it's the host AH (AH-uniform compliance rollup).
    belongs_to :account_holder, AccountHolder
    belongs_to :counterparty, Counterparty
    belongs_to :beneficial_owner, BeneficialOwner

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    field :legal_entity_number, :string

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

  @doc """
  Default changeset for standalone LegalEntity update where the caller already
  has every field in `attrs` (including identity / parent FKs). Used by
  `LegalEntityChangeEventContext` recovery paths and direct LE update via the
  nested PUT routes on the parent's controller.

  For cast_assoc paths from AccountHolder / Counterparty / BeneficialOwner,
  use the per-parent named changesets below — they put_change `subject_type`
  and (for CP/BO) `account_holder_id` so the parent context controls
  attribution and the caller cannot override it via attrs.
  """
  def changeset(legal_entity, attrs) do
    legal_entity
    |> base_changeset(attrs)
    |> cast(attrs, [:subject_type, :account_holder_id, :counterparty_id, :beneficial_owner_id])
  end

  @doc """
  Changeset for an AccountHolder-owned LegalEntity, used via
  `cast_assoc(:legal_entity, with: &LegalEntity.account_holder_changeset/2)`
  from `AccountHolder.changeset/2`.

  Ecto's `has_one :legal_entity, foreign_key: :account_holder_id` on AccountHolder
  injects `account_holder_id` after the parent AH is inserted. This changeset
  only forces `subject_type` via `put_change`.
  """
  def account_holder_changeset(legal_entity, attrs) do
    legal_entity
    |> base_changeset(attrs)
    |> put_change(:subject_type, :account_holder)
  end

  @doc """
  Changeset for a Counterparty-owned LegalEntity, used via
  `cast_assoc(:legal_entity, with: ...)` from `Counterparty.changeset/2`.

  `account_holder_id` is explicit because the host AH is known at write time
  (Counterparty carries its own `account_holder_id` column). Ecto's
  `has_one :legal_entity, foreign_key: :counterparty_id` on Counterparty
  injects `counterparty_id` after the parent CP is inserted.
  """
  def counterparty_changeset(legal_entity, attrs, account_holder_id)
      when is_binary(account_holder_id) do
    legal_entity
    |> base_changeset(attrs)
    |> put_change(:subject_type, :counterparty)
    |> put_change(:account_holder_id, account_holder_id)
  end

  @doc """
  Changeset for a BeneficialOwner-owned LegalEntity, used via
  `cast_assoc(:legal_entity, with: ...)` from `BeneficialOwner.changeset/2`.

  `account_holder_id` is explicit because every LE row carries the
  AH-uniform rollup. `counterparty_id` is optional: when supplied, the
  BO sits under a Counterparty (subject_type `:counterparty_beneficial_owner`);
  when nil, the BO sits under the host AccountHolder
  (subject_type `:account_holder_beneficial_owner`). The
  `legal_entities_subject_fk_consistency` CHECK constraint validates the
  (subject_type, parent-FK presence) tuple at the DB layer.

  Ecto's `has_one :legal_entity, foreign_key: :beneficial_owner_id` on
  BeneficialOwner injects `beneficial_owner_id` after the parent BO is
  inserted.
  """
  def beneficial_owner_changeset(legal_entity, attrs, account_holder_id, counterparty_id \\ nil)
      when is_binary(account_holder_id) and
             (is_nil(counterparty_id) or is_binary(counterparty_id)) do
    legal_entity
    |> base_changeset(attrs)
    |> put_change(:subject_type, beneficial_owner_subject_type(counterparty_id))
    |> put_change(:account_holder_id, account_holder_id)
    |> maybe_put_counterparty_id(counterparty_id)
    |> check_constraint(:subject_type,
      name: :legal_entities_subject_fk_consistency,
      message: "subject_type and parent foreign keys are inconsistent"
    )
  end

  defp beneficial_owner_subject_type(nil), do: :account_holder_beneficial_owner
  defp beneficial_owner_subject_type(_counterparty_id), do: :counterparty_beneficial_owner

  defp maybe_put_counterparty_id(changeset, nil), do: changeset

  defp maybe_put_counterparty_id(changeset, counterparty_id),
    do: put_change(changeset, :counterparty_id, counterparty_id)

  # Shared body — identity field cast + validations + nested addresses /
  # phone numbers / identifications. `subject_type` and the three parent FKs
  # are NOT touched here; the per-parent public changesets above own them.
  defp base_changeset(legal_entity, attrs) do
    changeset =
      legal_entity
      |> cast(attrs, [
        :legal_entity_type,
        :legal_structure,
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
        :institution_type,
        :has_physical_presence,
        :jurisdiction_cooperative,
        :legal_entity_number,
        :tenant_id
      ])
      |> validate_required([:legal_entity_type, :tenant_id])
      |> AtomicFi.Identifier.put_default(:legal_entity_number, :le)
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
