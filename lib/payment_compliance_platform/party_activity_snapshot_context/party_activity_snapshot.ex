defmodule PaymentCompliancePlatform.PartyActivitySnapshotContext.PartyActivitySnapshot do
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.AccountHolderContext.AccountHolder
  alias PaymentCompliancePlatform.TenantContext.Tenant

  @typedoc """
  PartyActivitySnapshot — period-level AML monitoring summary for an AccountHolder.

  Distinct from `AccountActivitySnapshot`, which aggregates ledger-level debit/credit
  activity for a specific PaymentAccount (camt:052/camt:053). PartyActivitySnapshot
  summarises *party-level* compliance signals across a reporting window — KYC status
  transitions, screening volume and hit rate, aggregate transaction shape, and SAR
  candidacy.

  ## Regulatory Alignment

  - **FATF Recommendation 10** — ongoing CDD. Snapshot captures kyc_status /
    risk_level at both ends of the period to detect deterioration.
  - **FinCEN AML** — 31 CFR §1020.320 SAR filing thresholds. `sar_indicator`
    flags periods where activity justifies SAR consideration.

  ## Attributes

  * `id` - UUID primary key
  * `account_holder_id` - FK to AccountHolder (required)
  * `period_type` - Reporting cadence (`:daily` | `:weekly` | `:monthly` | `:quarterly`)
  * `period_start` / `period_end` - Reporting window (inclusive dates)
  * `kyc_status_at_start` / `kyc_status_at_end` - Snapshot of AccountHolder.kyc_status
  * `risk_level_at_start` / `risk_level_at_end` - Snapshot of AccountHolder.risk_level
  * `total_screenings` - Compliance screenings run in the period
  * `screening_hits` - Potential/confirmed matches in the period
  * `transaction_count` - Transactions in the period
  * `total_debit_amount` / `total_credit_amount` - Aggregates (minor currency units)
  * `high_risk_transaction_count` - Transactions exceeding risk thresholds
  * `sar_indicator` - SAR filing consideration flag
  * `notes` - Free-text analyst notes
  * `tenant_id` - FK to Tenant for multi-tenancy isolation (RLS)
  * `inserted_at` / `updated_at` - Timestamps
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @kyc_statuses [:not_started, :in_progress, :approved, :rejected, :expired]
  @risk_levels [:low, :medium, :high, :very_high]
  @period_types [:daily, :weekly, :monthly, :quarterly]

  @derive {
    Flop.Schema,
    filterable: [
      :id,
      :tenant_id,
      :account_holder_id,
      :period_type,
      :period_start,
      :period_end,
      :sar_indicator
    ],
    sortable: [
      :id,
      :inserted_at,
      :updated_at,
      :period_start,
      :period_end,
      :period_type,
      :transaction_count,
      :screening_hits
    ],
    default_limit: 20,
    max_limit: 100
  }

  # ── OpenAPI annotations ──────────────────────────────────────────────────────

  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{
      type: :string,
      enum: Enum.map(@period_types, &Atom.to_string/1),
      description:
        "Reporting period cadence — daily/weekly/monthly snapshots feed ongoing CDD (FATF Rec 10); " <>
          "quarterly snapshots support SAR narrative evidence (FinCEN 31 CFR §1020.320)."
    },
    key: :period_type
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :date,
      description: "Start of the reporting period (inclusive)"
    },
    key: :period_start
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :date,
      description: "End of the reporting period (inclusive)"
    },
    key: :period_end
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: Enum.map(@kyc_statuses, &Atom.to_string/1),
      description: "AccountHolder.kyc_status at period open"
    },
    key: :kyc_status_at_start
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: Enum.map(@kyc_statuses, &Atom.to_string/1),
      description: "AccountHolder.kyc_status at period close"
    },
    key: :kyc_status_at_end
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: Enum.map(@risk_levels, &Atom.to_string/1),
      description: "AccountHolder.risk_level at period open"
    },
    key: :risk_level_at_start
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: Enum.map(@risk_levels, &Atom.to_string/1),
      description: "AccountHolder.risk_level at period close"
    },
    key: :risk_level_at_end
  )

  open_api_property(
    schema: %Schema{type: :integer, description: "Compliance screenings run in the period"},
    key: :total_screenings
  )

  open_api_property(
    schema: %Schema{type: :integer, description: "Potential/confirmed screening matches"},
    key: :screening_hits
  )

  open_api_property(
    schema: %Schema{type: :integer, description: "Transactions in the period"},
    key: :transaction_count
  )

  open_api_property(
    schema: %Schema{type: :integer, description: "Total debit amount (minor currency units)"},
    key: :total_debit_amount
  )

  open_api_property(
    schema: %Schema{type: :integer, description: "Total credit amount (minor currency units)"},
    key: :total_credit_amount
  )

  open_api_property(
    schema: %Schema{type: :integer, description: "Transactions exceeding risk thresholds"},
    key: :high_risk_transaction_count
  )

  open_api_property(
    schema: %Schema{
      type: :boolean,
      description: "SAR (Suspicious Activity Report) filing consideration flag"
    },
    key: :sar_indicator
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
    title: "PartyActivitySnapshot",
    description:
      "Party-level AML monitoring snapshot for an AccountHolder. Captures KYC/risk transitions, " <>
        "screening activity, transaction shape, and SAR candidacy across a reporting window " <>
        "(FATF Rec 10 ongoing CDD · FinCEN 31 CFR §1020.320 SAR).",
    required: [:account_holder_id, :period_type, :period_start, :period_end, :tenant_id],
    properties: [
      :id,
      :account_holder_id,
      :period_type,
      :period_start,
      :period_end,
      :kyc_status_at_start,
      :kyc_status_at_end,
      :risk_level_at_start,
      :risk_level_at_end,
      :total_screenings,
      :screening_hits,
      :transaction_count,
      :total_debit_amount,
      :total_credit_amount,
      :high_risk_transaction_count,
      :sar_indicator,
      :notes,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "party_activity_snapshots" do
    field :period_type, Ecto.Enum, values: @period_types

    field :period_start, :date
    field :period_end, :date

    field :kyc_status_at_start, Ecto.Enum, values: @kyc_statuses
    field :kyc_status_at_end, Ecto.Enum, values: @kyc_statuses

    field :risk_level_at_start, Ecto.Enum, values: @risk_levels
    field :risk_level_at_end, Ecto.Enum, values: @risk_levels

    field :total_screenings, :integer, default: 0
    field :screening_hits, :integer, default: 0

    field :transaction_count, :integer, default: 0
    field :total_debit_amount, :integer, default: 0
    field :total_credit_amount, :integer, default: 0
    field :high_risk_transaction_count, :integer, default: 0

    field :sar_indicator, :boolean, default: false

    field :notes, :string

    belongs_to :account_holder, AccountHolder
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :account_holder_id,
      :period_type,
      :period_start,
      :period_end,
      :kyc_status_at_start,
      :kyc_status_at_end,
      :risk_level_at_start,
      :risk_level_at_end,
      :notes,
      :tenant_id
    ])
    |> maybe_cast_with_default(attrs, :total_screenings, 0)
    |> maybe_cast_with_default(attrs, :screening_hits, 0)
    |> maybe_cast_with_default(attrs, :transaction_count, 0)
    |> maybe_cast_with_default(attrs, :total_debit_amount, 0)
    |> maybe_cast_with_default(attrs, :total_credit_amount, 0)
    |> maybe_cast_with_default(attrs, :high_risk_transaction_count, 0)
    |> maybe_cast_with_default(attrs, :sar_indicator, false)
    |> validate_required([
      :account_holder_id,
      :period_type,
      :period_start,
      :period_end,
      :tenant_id
    ])
    |> validate_period_order()
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:account_holder_id, :period_type, :period_start, :tenant_id],
      name: :party_activity_snapshots_holder_period_tenant_unique,
      message: "snapshot already exists for this holder/period"
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

  defp validate_period_order(changeset) do
    period_start = get_field(changeset, :period_start)
    period_end = get_field(changeset, :period_end)

    if period_start && period_end && Date.compare(period_start, period_end) == :gt do
      add_error(changeset, :period_end, "must be on or after period_start")
    else
      changeset
    end
  end
end
