defmodule AtomicFi.ComplianceScreeningContext.ComplianceScreening do
  @moduledoc """
  ISO 20022 compliance screening record (auth:018 / camt:998).

  One row per entity per screening run. Child rows in `sanctions_matches` and
  `blocklist_matches` carry the per-hit detail and reviewer decisions.

  ## Scope

  `scope` controls which part of the payment lifecycle triggered the screening:

  - `:account_holder` — onboarding / periodic CDD review
  - `:counterparty` — payment counterparty screening (ISO 20022 pacs.008 <Cdtr>/<Dbtr>)
  - `:payment_account` — account-level OFAC/blocklist gate
  - `:transaction` — real-time transaction screening

  ## Screening Type

  `screening_type` narrows the compliance check performed:

  - `:sanctions` — OFAC / Watchman SDN/EU/UN list
  - `:pep` — Politically Exposed Person
  - `:aml` — Anti-Money Laundering control / geographic risk
  - `:adverse_media` — Negative news screening

  ## False Positive Model

  `false_positive_qualifier` on the screening record captures an entity-level
  override (e.g. the entire screening is suppressed). Per-match overrides live
  on the child `SanctionsMatch` / `BlocklistMatch` rows.

  ## AML Fields

  AML control and geographic risk fields provide camt:998-level risk signals:
  - `aml_control_flag` / `aml_control_count` — unusual transaction frequency
  - `aml_geographic_risk_flag` / `aml_high_risk_country` — FATF high-risk jurisdiction

  ## PEP Fields

  `pep_indicator` + `pep_list_name` — whether the screened entity appears on a PEP list.

  ## ISO 20022

  Maps to `auth:018 ComplianceCheckType` and `camt:998 ProprietaryMessage`.
  """

  use AtomicFi.Schema

  alias AtomicFi.ComplianceScreeningContext.BlocklistMatch
  alias AtomicFi.ComplianceScreeningContext.SanctionsMatch
  alias AtomicFi.LegalEntityContext.LegalEntity
  alias AtomicFi.TenantContext.Tenant

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [
      :id,
      :tenant_id,
      :legal_entity_id,
      :payment_account_id,
      :scope,
      :screening_type,
      :screening_status,
      :false_positive_qualifier,
      :manual_review_required,
      :pep_indicator
    ],
    sortable: [:id, :inserted_at, :updated_at, :screened_at, :screening_score],
    default_limit: 20,
    max_limit: 100
  }

  # ---------------------------------------------------------------------------
  # OpenAPI annotations
  # ---------------------------------------------------------------------------

  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{
      type: :string,
      enum: [
        "account_holder",
        "beneficial_owner",
        "counterparty",
        "payment_account",
        "transaction"
      ]
    },
    key: :scope
  )

  open_api_property(
    schema: %Schema{type: :string, enum: ["sanctions", "pep", "aml", "adverse_media"]},
    key: :screening_type
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      enum: ["pending", "pass", "potential_match", "blocked", "escalated"]
    },
    key: :screening_status
  )

  open_api_property(
    schema: %Schema{type: :number, format: :decimal, nullable: true},
    key: :screening_score
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      enum: ["individual", "company", "crypto_address", "payment_account"]
    },
    key: :screened_entity_type
  )

  open_api_property(schema: %Schema{type: :string}, key: :screened_entity_name)

  open_api_property(schema: %Schema{type: :integer, nullable: true}, key: :match_count)

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", nullable: true},
    key: :screened_at
  )

  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :screening_rules)

  # Sanctions sub-status (ISO 20022 auth:018 SanctionsCheckType)
  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: ["cleared", "pending", "match", "failed"]
    },
    key: :sanctions_screening_status
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", nullable: true},
    key: :sanctions_screening_date
  )

  # PEP fields
  open_api_property(schema: %Schema{type: :boolean, nullable: true}, key: :pep_indicator)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :pep_list_name)

  # AML fields
  open_api_property(
    schema: %Schema{type: :number, format: :decimal, nullable: true},
    key: :aml_risk_score
  )

  open_api_property(schema: %Schema{type: :boolean, nullable: true}, key: :aml_control_flag)
  open_api_property(schema: %Schema{type: :integer, nullable: true}, key: :aml_control_count)

  open_api_property(
    schema: %Schema{type: :boolean, nullable: true},
    key: :aml_geographic_risk_flag
  )

  open_api_property(
    schema: %Schema{type: :string, nullable: true},
    key: :aml_high_risk_country
  )

  # Entity-level false positive qualifier
  open_api_property(
    schema: %Schema{
      type: :string,
      enum: ["none", "manual_override", "auto_suppressed"]
    },
    key: :false_positive_qualifier
  )

  open_api_property(schema: %Schema{type: :boolean}, key: :manual_review_required)

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", nullable: true},
    key: :reviewed_at
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, nullable: true},
    key: :reviewed_by_user_id
  )

  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :review_notes)

  open_api_property(schema: %Schema{type: :integer, nullable: true}, key: :escalation_level)

  open_api_property(
    schema: %Schema{type: :string, nullable: true},
    key: :compliance_screening_number
  )

  # Primary anchor — exactly one of (legal_entity_id, payment_account_id) is set
  # per DB CHECK. legal_entity_id anchors party screenings (PII subject);
  # payment_account_id anchors instrument screenings (crypto wallet / IBAN).
  open_api_property(
    schema: %Schema{type: :string, format: :uuid, nullable: true},
    key: :legal_entity_id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, nullable: true},
    key: :payment_account_id
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

  # Per-hit child collections — readOnly on the response surface so
  # rules can read `compliance_screenings[].blocklist_matches[]` or
  # `.sanctions_matches[]` to dispatch on the source list (OFAC SDN vs
  # internal chargeback-fraud ring vs PEP, etc.) without having to add
  # a new `screening_type` enum value per list.
  open_api_property(
    schema: %Schema{
      type: :array,
      readOnly: true,
      items: %OpenApiSpex.Reference{"$ref": "#/components/schemas/SanctionsMatchResponse"}
    },
    key: :sanctions_matches
  )

  open_api_property(
    schema: %Schema{
      type: :array,
      readOnly: true,
      items: %OpenApiSpex.Reference{"$ref": "#/components/schemas/BlocklistMatchResponse"}
    },
    key: :blocklist_matches
  )

  open_api_schema(
    title: "ComplianceScreening",
    description:
      "ISO 20022 compliance screening record (auth:018 / camt:998). " <>
        "One row per entity per screening run. " <>
        "scope controls the payment lifecycle gate; screening_type narrows the check performed. " <>
        "Child sanctions_matches and blocklist_matches carry per-hit detail and reviewer decisions.",
    required: [
      :scope,
      :screening_type,
      :screening_status,
      :screened_entity_type,
      :screened_entity_name
    ],
    properties: [
      :id,
      :scope,
      :screening_type,
      :screening_status,
      :screening_score,
      :screened_entity_type,
      :screened_entity_name,
      :match_count,
      :screened_at,
      :screening_rules,
      :sanctions_screening_status,
      :sanctions_screening_date,
      :pep_indicator,
      :pep_list_name,
      :aml_risk_score,
      :aml_control_flag,
      :aml_control_count,
      :aml_geographic_risk_flag,
      :aml_high_risk_country,
      :false_positive_qualifier,
      :manual_review_required,
      :reviewed_at,
      :reviewed_by_user_id,
      :review_notes,
      :escalation_level,
      :compliance_screening_number,
      :legal_entity_id,
      :payment_account_id,
      :tenant_id,
      :inserted_at,
      :updated_at,
      :sanctions_matches,
      :blocklist_matches
    ]
  )

  # ---------------------------------------------------------------------------
  # Schema
  # ---------------------------------------------------------------------------

  typed_schema "compliance_screenings" do
    field :scope, Ecto.Enum,
      values: [:account_holder, :beneficial_owner, :counterparty, :payment_account, :transaction]

    field :screening_type, Ecto.Enum, values: [:sanctions, :pep, :aml, :adverse_media]

    field :screening_status, Ecto.Enum,
      values: [:pending, :pass, :potential_match, :blocked, :escalated],
      default: :pending

    field :screening_score, :decimal

    field :screened_entity_type, Ecto.Enum,
      values: [:individual, :company, :crypto_address, :payment_account]

    field :screened_entity_name, :string
    field :match_count, :integer, default: 0

    field :screened_at, :utc_datetime_usec
    field :screening_rules, :string

    # Sanctions sub-status (auth:018 SanctionsCheckType)
    field :sanctions_screening_status, Ecto.Enum, values: [:cleared, :pending, :match, :failed]

    field :sanctions_screening_date, :utc_datetime_usec

    # PEP fields
    field :pep_indicator, :boolean, default: false
    field :pep_list_name, :string

    # AML fields
    field :aml_risk_score, :decimal
    field :aml_control_flag, :boolean, default: false
    field :aml_control_count, :integer
    field :aml_geographic_risk_flag, :boolean, default: false
    field :aml_high_risk_country, :string

    # Entity-level false positive (per-match overrides live on child rows)
    field :false_positive_qualifier, Ecto.Enum,
      values: [:none, :manual_override, :auto_suppressed],
      default: :none

    field :manual_review_required, :boolean, default: false
    field :reviewed_at, :utc_datetime_usec
    field :reviewed_by_user_id, :binary_id
    field :review_notes, :string
    field :escalation_level, :integer

    # Opaque SoE identifier
    field :compliance_screening_number, :string

    # Primary anchor — exactly one set per DB CHECK constraint
    # `compliance_screenings_exactly_one_anchor`. legal_entity_id anchors party
    # screenings (Watchman PII pass); payment_account_id anchors instrument
    # screenings (Watchman crypto-address / IBAN pass).
    belongs_to :legal_entity, LegalEntity
    field :payment_account_id, :binary_id

    # Child match rows
    has_many :sanctions_matches, SanctionsMatch
    has_many :blocklist_matches, BlocklistMatch

    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(compliance_screening, attrs) do
    compliance_screening
    |> cast(attrs, [
      :scope,
      :screening_type,
      :screening_status,
      :screening_score,
      :screened_entity_type,
      :screened_entity_name,
      :match_count,
      :screened_at,
      :screening_rules,
      :sanctions_screening_status,
      :sanctions_screening_date,
      :pep_indicator,
      :pep_list_name,
      :aml_risk_score,
      :aml_control_flag,
      :aml_control_count,
      :aml_geographic_risk_flag,
      :aml_high_risk_country,
      :false_positive_qualifier,
      :manual_review_required,
      :reviewed_at,
      :reviewed_by_user_id,
      :review_notes,
      :escalation_level,
      :compliance_screening_number,
      :legal_entity_id,
      :payment_account_id,
      :tenant_id
    ])
    |> validate_required([
      :scope,
      :screening_type,
      :screening_status,
      :screened_entity_type,
      :screened_entity_name,
      :tenant_id
    ])
    |> validate_number(:screening_score,
      greater_than_or_equal_to: Decimal.new(0),
      less_than_or_equal_to: Decimal.new(100)
    )
    |> validate_number(:escalation_level,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 5
    )
    |> foreign_key_constraint(:legal_entity_id)
    |> foreign_key_constraint(:tenant_id)
    |> check_constraint(:legal_entity_id,
      name: :compliance_screenings_exactly_one_anchor,
      message: "exactly one of legal_entity_id or payment_account_id must be set"
    )
  end
end
