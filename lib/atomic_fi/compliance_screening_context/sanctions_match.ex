defmodule AtomicFi.ComplianceScreeningContext.SanctionsMatch do
  @moduledoc """
  One Watchman / OFAC sanctions list match within a ComplianceScreening.

  Each row represents a single entity returned by the Watchman API that matched
  against the screened party. Watchman sub-objects (addresses, business, person,
  contact data) are stored as typed embedded schemas — structured and queryable
  without requiring separate tables for read-only API response data.

  ## False Positive Deduplication

  `false_positive_qualifier` persists reviewer decisions across re-screenings:
  - `:manual_override` — compliance reviewer confirmed: not a real match
  - `:auto_suppressed` — system detected a prior `manual_override` for the same
    `source_id` within this tenant; written automatically on re-screen

  Before Watchman scoring, `ComplianceScreeningContext` queries:

      SELECT source_id FROM sanctions_matches
      WHERE tenant_id = $tenant_id
        AND source_id = $source_id
        AND false_positive_qualifier IN ('manual_override', 'auto_suppressed')
      LIMIT 1;

  Matches found are written with `false_positive_qualifier: :auto_suppressed`
  and excluded from `screening_score` calculation.

  ## ISO 20022

  Maps to `ComplianceScreening.sanctionsMatchType` (auth:018) and Watchman
  SDN/EU/UN list entries referenced in the screening record.
  """

  use AtomicFi.Schema

  alias AtomicFi.TenantContext.Tenant

  # ---------------------------------------------------------------------------
  # Typed embedded schemas for Watchman API sub-objects
  # No Watchman.* types are referenced here — data is normalized by ScreeningEngine
  # ---------------------------------------------------------------------------

  defmodule WatchmanAddress do
    @moduledoc "Normalized Watchman address entry."
    use AtomicFi.Schema

    @primary_key false
    typed_embedded_schema do
      open_api_property(schema: %Schema{type: :string, nullable: true}, key: :line1)
      field :line1, :string

      open_api_property(schema: %Schema{type: :string, nullable: true}, key: :line2)
      field :line2, :string

      open_api_property(schema: %Schema{type: :string, nullable: true}, key: :city)
      field :city, :string

      open_api_property(schema: %Schema{type: :string, nullable: true}, key: :region)
      field :region, :string

      open_api_property(schema: %Schema{type: :string, nullable: true}, key: :postal_code)
      field :postal_code, :string

      open_api_property(schema: %Schema{type: :string, nullable: true}, key: :country)
      field :country, :string

      open_api_property(schema: %Schema{type: :string, nullable: true}, key: :type)
      field :type, :string

      open_api_schema(
        title: "WatchmanAddress",
        description: "Normalized Watchman address entry",
        properties: [:line1, :line2, :city, :region, :postal_code, :country, :type]
      )
    end

    @doc false
    def changeset(address, attrs) do
      cast(address, attrs, [:line1, :line2, :city, :region, :postal_code, :country, :type])
    end
  end

  defmodule WatchmanBusiness do
    @moduledoc "Normalized Watchman business block."
    use AtomicFi.Schema

    @primary_key false
    typed_embedded_schema do
      open_api_property(schema: %Schema{type: :string, nullable: true}, key: :name)
      field :name, :string

      open_api_property(schema: %Schema{type: :string, nullable: true}, key: :registration_number)
      field :registration_number, :string

      open_api_property(schema: %Schema{type: :string, nullable: true}, key: :incorporation_date)
      field :incorporation_date, :string

      open_api_property(schema: %Schema{type: :string, nullable: true}, key: :dissolved_date)
      field :dissolved_date, :string

      open_api_schema(
        title: "WatchmanBusiness",
        description: "Normalized Watchman business block",
        properties: [:name, :registration_number, :incorporation_date, :dissolved_date]
      )
    end

    @doc false
    def changeset(business, attrs) do
      cast(business, attrs, [:name, :registration_number, :incorporation_date, :dissolved_date])
    end
  end

  defmodule WatchmanPerson do
    @moduledoc "Normalized Watchman person block."
    use AtomicFi.Schema

    @primary_key false
    typed_embedded_schema do
      open_api_property(schema: %Schema{type: :string, nullable: true}, key: :given_name)
      field :given_name, :string

      open_api_property(schema: %Schema{type: :string, nullable: true}, key: :family_name)
      field :family_name, :string

      open_api_property(schema: %Schema{type: :string, nullable: true}, key: :dob)
      field :dob, :string

      open_api_property(schema: %Schema{type: :string, nullable: true}, key: :gender)
      field :gender, :string

      open_api_property(
        schema: %Schema{type: :array, items: %Schema{type: :string}},
        key: :nationalities
      )

      field :nationalities, {:array, :string}, default: []

      open_api_schema(
        title: "WatchmanPerson",
        description: "Normalized Watchman person block",
        properties: [:given_name, :family_name, :dob, :gender, :nationalities]
      )
    end

    @doc false
    def changeset(person, attrs) do
      cast(person, attrs, [:given_name, :family_name, :dob, :gender, :nationalities])
    end
  end

  defmodule WatchmanContact do
    @moduledoc "Normalized Watchman contact block."
    use AtomicFi.Schema

    @primary_key false
    typed_embedded_schema do
      open_api_property(
        schema: %Schema{type: :array, items: %Schema{type: :string}},
        key: :emails
      )

      field :emails, {:array, :string}, default: []

      open_api_property(
        schema: %Schema{type: :array, items: %Schema{type: :string}},
        key: :phones
      )

      field :phones, {:array, :string}, default: []

      open_api_property(
        schema: %Schema{type: :array, items: %Schema{type: :string}},
        key: :websites
      )

      field :websites, {:array, :string}, default: []

      open_api_schema(
        title: "WatchmanContact",
        description: "Normalized Watchman contact block",
        properties: [:emails, :phones, :websites]
      )
    end

    @doc false
    def changeset(contact, attrs) do
      cast(contact, attrs, [:emails, :phones, :websites])
    end
  end

  # ---------------------------------------------------------------------------
  # SanctionsMatch schema
  # ---------------------------------------------------------------------------

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [:id, :tenant_id, :compliance_screening_id, :source_id, :false_positive_qualifier],
    sortable: [:id, :inserted_at, :match_score],
    default_limit: 50,
    max_limit: 200
  }

  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, readOnly: true},
    key: :compliance_screening_id
  )

  open_api_property(schema: %Schema{type: :string}, key: :matched_name)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :matched_entity_type)
  open_api_property(schema: %Schema{type: :number, format: :float}, key: :match_score)

  open_api_property(
    schema: %Schema{type: :string, enum: ["exact", "fuzzy", "ubo", "entity"]},
    key: :sanctions_match_type
  )

  open_api_property(schema: %Schema{type: :string}, key: :source_list)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :source_id)
  open_api_property(schema: %Schema{type: :object, nullable: true}, key: :source_data)

  open_api_property(
    schema: %Schema{
      type: :array,
      items: %OpenApiSpex.Reference{"$ref": "#/components/schemas/WatchmanAddressResponse"}
    },
    key: :addresses
  )

  open_api_property(
    schema: %OpenApiSpex.Reference{"$ref": "#/components/schemas/WatchmanBusinessResponse"},
    key: :business_data
  )

  open_api_property(
    schema: %OpenApiSpex.Reference{"$ref": "#/components/schemas/WatchmanPersonResponse"},
    key: :person_data
  )

  open_api_property(
    schema: %OpenApiSpex.Reference{"$ref": "#/components/schemas/WatchmanContactResponse"},
    key: :contact_data
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      enum: ["none", "manual_override", "auto_suppressed"]
    },
    key: :false_positive_qualifier
  )

  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :review_notes)

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, nullable: true},
    key: :reviewed_by_user_id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", nullable: true},
    key: :reviewed_at
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", nullable: true},
    key: :list_synced_at
  )

  open_api_property(schema: %Schema{type: :object, nullable: true}, key: :list_sources)

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
    title: "SanctionsMatch",
    description:
      "One Watchman / OFAC sanctions match. false_positive_qualifier persists reviewer decisions " <>
        "across re-screenings: :manual_override (human override) or :auto_suppressed (system dedup). " <>
        "ISO 20022 auth:018.",
    required: [:matched_name, :match_score, :source_list, :sanctions_match_type],
    properties: [
      :id,
      :compliance_screening_id,
      :matched_name,
      :matched_entity_type,
      :match_score,
      :sanctions_match_type,
      :source_list,
      :source_id,
      :source_data,
      :addresses,
      :business_data,
      :person_data,
      :contact_data,
      :false_positive_qualifier,
      :review_notes,
      :reviewed_by_user_id,
      :reviewed_at,
      :list_synced_at,
      :list_sources,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "sanctions_matches" do
    field :matched_name, :string
    field :matched_entity_type, :string

    field :match_score, :float

    field :sanctions_match_type, Ecto.Enum,
      values: [:exact, :fuzzy, :ubo, :entity],
      default: :fuzzy

    field :source_list, :string
    field :source_id, :string
    field :source_data, :map

    embeds_many :addresses, WatchmanAddress, on_replace: :delete
    embeds_one :business_data, WatchmanBusiness, on_replace: :delete
    embeds_one :person_data, WatchmanPerson, on_replace: :delete
    embeds_one :contact_data, WatchmanContact, on_replace: :delete

    field :false_positive_qualifier, Ecto.Enum,
      values: [:none, :manual_override, :auto_suppressed],
      default: :none

    field :review_notes, :string
    field :reviewed_by_user_id, :binary_id
    field :reviewed_at, :utc_datetime_usec

    # Watchman list metadata at the time this specific match was found
    field :list_synced_at, :utc_datetime_usec
    field :list_sources, :map

    belongs_to :compliance_screening,
               AtomicFi.ComplianceScreeningContext.ComplianceScreening

    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(sanctions_match, attrs) do
    sanctions_match
    |> cast(attrs, [
      :matched_name,
      :matched_entity_type,
      :match_score,
      :sanctions_match_type,
      :source_list,
      :source_id,
      :source_data,
      :false_positive_qualifier,
      :review_notes,
      :reviewed_by_user_id,
      :reviewed_at,
      :list_synced_at,
      :list_sources,
      :compliance_screening_id,
      :tenant_id
    ])
    |> validate_required([:matched_name, :match_score, :source_list, :tenant_id])
    |> cast_embed(:addresses)
    |> cast_embed(:business_data)
    |> cast_embed(:person_data)
    |> cast_embed(:contact_data)
    |> foreign_key_constraint(:compliance_screening_id)
    |> foreign_key_constraint(:tenant_id)
  end
end
