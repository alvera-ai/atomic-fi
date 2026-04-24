defmodule PaymentCompliancePlatform.RiskClassificationContext.RiskClassification do
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.AccountHolderContext.AccountHolder
  alias PaymentCompliancePlatform.ComplianceScreeningContext.ComplianceScreening
  alias PaymentCompliancePlatform.TenantContext.Tenant
  alias PaymentCompliancePlatform.UserContext.User

  @typedoc """
  RiskClassification — formal risk-level record for an AccountHolder.

  Drives the LedgerAccount limit cascade: the MASTER LedgerAccount velocity
  limit is a function of the currently active RiskClassification.risk_level
  for the holder. Exactly one `is_active = true` classification exists per
  `(account_holder_id, tenant_id)` at any time — enforced by a partial unique
  index and by the context, which deactivates any prior active record when
  a new active classification is created.

  ## Regulatory Alignment

  - **ISO 20022 auth:018** — CustomerRiskAssessment. Each RiskClassification
    row corresponds to a risk assessment outcome (CustomerIdnAssmt).
  - **FATF Recommendation 10** — risk-based CDD. The classification level
    determines the depth of CDD / EDD required on the holder going forward.

  ## Attributes

  * `id` - UUID primary key
  * `account_holder_id` - FK to AccountHolder (required)
  * `risk_level` - `:low` | `:medium` | `:high` | `:very_high`
  * `classification_reason` - Human-readable justification (required)
  * `effective_from` - Start date of the classification (inclusive)
  * `effective_until` - End date, nullable (open-ended if nil)
  * `is_active` - True when this is the current active classification
  * `classified_by_user_id` - FK to User (nil → auto-classified by engine)
  * `compliance_screening_id` - FK to ComplianceScreening that drove this
  * `notes` - Free-text analyst notes
  * `tenant_id` - FK to Tenant for multi-tenancy isolation (RLS)
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @risk_levels [:low, :medium, :high, :very_high]

  @derive {
    Flop.Schema,
    filterable: [
      :id,
      :tenant_id,
      :account_holder_id,
      :risk_level,
      :is_active,
      :effective_from,
      :effective_until,
      :classified_by_user_id,
      :compliance_screening_id
    ],
    sortable: [:id, :inserted_at, :updated_at, :effective_from, :effective_until, :risk_level],
    default_limit: 20,
    max_limit: 100
  }

  # ── OpenAPI annotations ──────────────────────────────────────────────────────

  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{
      type: :string,
      enum: Enum.map(@risk_levels, &Atom.to_string/1),
      description: "Risk level driving the LedgerAccount limit cascade"
    },
    key: :risk_level
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      description: "Human-readable justification for the classification"
    },
    key: :classification_reason
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :date,
      description: "Start date of the classification (inclusive)"
    },
    key: :effective_from
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :date,
      nullable: true,
      description: "End date of the classification (exclusive), nil = open-ended"
    },
    key: :effective_until
  )

  open_api_property(
    schema: %Schema{
      type: :boolean,
      default: true,
      description: "True when this is the current active classification for the holder"
    },
    key: :is_active
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      description: "User who performed the classification (nil = auto-classified by engine)"
    },
    key: :classified_by_user_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      description: "ComplianceScreening that drove this classification"
    },
    key: :compliance_screening_id
  )

  open_api_property(
    schema: %Schema{type: :string, nullable: true, description: "Free-text analyst notes"},
    key: :notes
  )

  open_api_property(schema: %Schema{type: :string, format: :uuid}, key: :account_holder_id)
  open_api_property(schema: %Schema{type: :string, format: :uuid}, key: :tenant_id)

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", readOnly: true},
    key: :inserted_at
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", readOnly: true},
    key: :updated_at
  )

  open_api_schema(
    title: "RiskClassification",
    description:
      "Formal risk classification record for an AccountHolder. Drives the LedgerAccount " <>
        "limit cascade. Exactly one is_active=true record exists per (holder, tenant) at a time. " <>
        "Maps to ISO 20022 auth:018 (CustomerRiskAssessment) and FATF Rec 10 (risk-based CDD).",
    required: [
      :account_holder_id,
      :risk_level,
      :classification_reason,
      :effective_from,
      :tenant_id
    ],
    properties: [
      :id,
      :account_holder_id,
      :risk_level,
      :classification_reason,
      :effective_from,
      :effective_until,
      :is_active,
      :classified_by_user_id,
      :compliance_screening_id,
      :notes,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "risk_classifications" do
    field :risk_level, Ecto.Enum, values: @risk_levels
    field :classification_reason, :string

    field :effective_from, :date
    field :effective_until, :date

    field :is_active, :boolean, default: true

    field :notes, :string

    belongs_to :account_holder, AccountHolder
    belongs_to :classified_by, User, foreign_key: :classified_by_user_id
    belongs_to :compliance_screening, ComplianceScreening
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(classification, attrs) do
    classification
    |> cast(attrs, [
      :account_holder_id,
      :risk_level,
      :classification_reason,
      :effective_from,
      :effective_until,
      :classified_by_user_id,
      :compliance_screening_id,
      :notes,
      :tenant_id
    ])
    |> maybe_cast_with_default(attrs, :is_active, true)
    |> validate_required([
      :account_holder_id,
      :risk_level,
      :classification_reason,
      :effective_from,
      :tenant_id
    ])
    |> validate_effective_range()
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:classified_by_user_id)
    |> foreign_key_constraint(:compliance_screening_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:account_holder_id, :tenant_id],
      name: :risk_classifications_one_active_per_holder_tenant,
      message: "another active classification exists for this account holder"
    )
  end

  # Cast a field only when explicitly provided and non-nil; otherwise use the given default.
  # Prevents ExOpenApiUtils nil values from overriding DB/Ecto defaults.
  defp maybe_cast_with_default(changeset, attrs, field, default) do
    value = Map.get(attrs, field)

    if is_nil(value) do
      Ecto.Changeset.cast(changeset, %{field => default}, [field])
    else
      Ecto.Changeset.cast(changeset, %{field => value}, [field])
    end
  end

  defp validate_effective_range(changeset) do
    effective_from = get_field(changeset, :effective_from)
    effective_until = get_field(changeset, :effective_until)

    if effective_from && effective_until &&
         Date.compare(effective_from, effective_until) == :gt do
      add_error(changeset, :effective_until, "must be on or after effective_from")
    else
      changeset
    end
  end
end
