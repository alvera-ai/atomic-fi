defmodule PaymentCompliancePlatform.AccountHolderContext.AccountHolder do
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.LegalEntityContext.LegalEntity
  alias PaymentCompliancePlatform.TenantContext.Tenant

  @typedoc """
  Account holder — the MDM subject that controls an account (ISO 20022 acmt:007, acmt:019).

  Operational state lives here. All PII lives in the linked LegalEntity.

  ## Attributes

  * `id` - UUID primary key
  * `legal_entity_id` - FK to LegalEntity (all PII / identity)
  * `external_id` - Upstream ID (Stripe/JPMC/Moov), unique per tenant
  * `holder_type` - `individual` | `organization`
  * `status` - `pending` | `active` | `suspended` | `closed`
  * `kyc_status` - `not_started` | `in_progress` | `approved` | `rejected` | `expired`
  * `risk_level` - `low` | `medium` | `high` | `very_high` | `prohibited`
  * `enabled_currencies` - ISO 4217 codes (each creates a Ledger)
  * `account_holder_number` - Opaque internal identifier
  * `onboarded_at` - Timestamp when account holder was onboarded
  * `last_reviewed_at` - Timestamp when account holder was last reviewed
  * `tenant_id` - FK to tenant for multi-tenancy isolation (RLS)
  * `inserted_at` - Timestamp when record was created
  * `updated_at` - Timestamp when record was last updated
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [:id, :tenant_id, :holder_type, :status, :kyc_status, :risk_level],
    sortable: [:id, :inserted_at, :updated_at, :holder_type, :status, :onboarded_at],
    default_limit: 20,
    max_limit: 100
  }

  # OpenAPI annotations
  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{type: :string, format: :uuid},
    key: :legal_entity_id
  )

  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :external_id)

  open_api_property(
    schema: %Schema{type: :string, enum: ["individual", "business", "trust", "nonprofit"]},
    key: :holder_type
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: ["pending", "active", "suspended", "closed", "flagged"]
    },
    key: :status
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: ["not_started", "in_progress", "approved", "rejected", "expired"]
    },
    key: :kyc_status
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: ["low", "medium", "high", "very_high"]
    },
    key: :risk_level
  )

  open_api_property(
    schema: %Schema{type: :array, nullable: true, items: %Schema{type: :string}},
    key: :enabled_currencies
  )

  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :account_holder_number)

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", nullable: true},
    key: :onboarded_at
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", nullable: true},
    key: :last_reviewed_at
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid},
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
    title: "AccountHolder",
    description:
      "Account holder — the MDM subject controlling an account. " <>
        "All PII lives in the linked LegalEntity (ISO 20022 acmt:007 / acmt:019).",
    required: [:legal_entity_id, :holder_type],
    properties: [
      :id,
      :legal_entity_id,
      :external_id,
      :holder_type,
      :status,
      :kyc_status,
      :risk_level,
      :enabled_currencies,
      :account_holder_number,
      :onboarded_at,
      :last_reviewed_at,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "account_holders" do
    belongs_to :legal_entity, LegalEntity

    field :external_id, :string

    field :holder_type, Ecto.Enum, values: [:individual, :business, :trust, :nonprofit]

    field :status, Ecto.Enum,
      values: [:pending, :active, :suspended, :closed, :flagged],
      default: :pending

    field :kyc_status, Ecto.Enum,
      values: [:not_started, :in_progress, :approved, :rejected, :expired],
      default: :not_started

    field :risk_level, Ecto.Enum,
      values: [:low, :medium, :high, :very_high],
      default: :low

    field :enabled_currencies, {:array, :string}, default: []

    field :account_holder_number, :string

    field :onboarded_at, :utc_datetime_usec
    field :last_reviewed_at, :utc_datetime_usec

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(account_holder, attrs) do
    account_holder
    |> cast(attrs, [
      :legal_entity_id,
      :external_id,
      :holder_type,
      :status,
      :kyc_status,
      :risk_level,
      :enabled_currencies,
      :account_holder_number,
      :onboarded_at,
      :last_reviewed_at,
      :tenant_id
    ])
    |> validate_required([:legal_entity_id, :holder_type, :tenant_id])
    |> foreign_key_constraint(:legal_entity_id)
    |> foreign_key_constraint(:tenant_id)
  end
end
