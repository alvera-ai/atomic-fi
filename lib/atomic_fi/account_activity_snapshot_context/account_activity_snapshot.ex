defmodule AtomicFi.AccountActivitySnapshotContext.AccountActivitySnapshot do
  use AtomicFi.Schema

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.LedgerAccountContext.LedgerAccount
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  alias AtomicFi.TenantContext.Tenant

  @typedoc """
  AccountActivitySnapshot — one row per reporting period for an AccountHolder/PaymentAccount.

  ## ISO 20022 Alignment

  Maps to two camt message families used for account monitoring and AML:

  - `camt:052` — BankToCustomerAccountReport (intraday / on-demand account activity)
  - `camt:053` — BankToCustomerStatement (end-of-day or periodic account statement)

  A `snapshot_type: :intraday` row corresponds to a camt:052 message (live view, partial period).
  A `snapshot_type: :daily | :weekly | :monthly` row corresponds to a camt:053 statement.

  ## FinCEN AML — Lookback Monitoring

  FinCEN SAR (Suspicious Activity Report) requirements (31 CFR §1020.320) mandate that
  FIs monitor account activity over rolling lookback windows (typically 90 days).
  The `flagged_for_review` boolean + `review_reason` surface transactions that exceed
  AML thresholds. `sar_reference` records the SAR filing reference once filed.

  ## Attributes

  * `id` - UUID primary key
  * `account_holder_id` - FK to AccountHolder (MDM subject, required)
  * `payment_account_id` - FK to PaymentAccount (optional — scopes to one payment account)
  * `ledger_account_id` - FK to LedgerAccount (optional — scopes to one ledger account)
  * `snapshot_type` - Reporting period type (`:intraday` | `:daily` | `:weekly` | `:monthly`)
  * `period_start` - Start of reporting period (inclusive)
  * `period_end` - End of reporting period (inclusive)
  * `opening_balance` - Balance at period start (minor currency units, nullable)
  * `closing_balance` - Balance at period end (minor currency units, nullable)
  * `currency` - ISO 4217 3-letter currency code
  * `total_debit_count` - Number of debit entries in the period
  * `total_credit_count` - Number of credit entries in the period
  * `total_debit_amount` - Total debit amount in minor currency units
  * `total_credit_amount` - Total credit amount in minor currency units
  * `transaction_count` - Total number of transactions (debit + credit)
  * `status` - Snapshot lifecycle status (`:pending` | `:computed` | `:published`)
  * `flagged_for_review` - AML review flag (true when activity triggers AML thresholds)
  * `review_reason` - Human-readable description of why this snapshot was flagged
  * `sar_reference` - SAR (Suspicious Activity Report) filing reference
  * `external_reference` - Caller-supplied idempotency key (unique per tenant when set)
  * `tenant_id` - FK to Tenant for multi-tenancy isolation (RLS)
  * `inserted_at` - Timestamp when record was created
  * `updated_at` - Timestamp when record was last updated
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [
      :id,
      :tenant_id,
      :account_holder_id,
      :payment_account_id,
      :ledger_account_id,
      :snapshot_type,
      :status,
      :currency,
      :flagged_for_review,
      :period_start,
      :period_end
    ],
    sortable: [
      :id,
      :inserted_at,
      :updated_at,
      :period_start,
      :period_end,
      :snapshot_type,
      :status,
      :transaction_count,
      :total_debit_amount,
      :total_credit_amount
    ],
    default_limit: 20,
    max_limit: 100
  }

  # ── OpenAPI annotations ──────────────────────────────────────────────────────

  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{
      type: :string,
      enum: ["intraday", "daily", "weekly", "monthly"],
      description:
        "Reporting period type — intraday maps to camt:052 (on-demand report); " <>
          "daily/weekly/monthly map to camt:053 (periodic statement)"
    },
    key: :snapshot_type
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :"date-time",
      description: "Start of the reporting period (inclusive)"
    },
    key: :period_start
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :"date-time",
      description: "End of the reporting period (inclusive)"
    },
    key: :period_end
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      description:
        "Balance at period start in minor currency units (camt:053 <Bal> OpeningBooked)"
    },
    key: :opening_balance
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      description: "Balance at period end in minor currency units (camt:053 <Bal> ClosingBooked)"
    },
    key: :closing_balance
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "ISO 4217 3-letter currency code (e.g. USD, EUR, GBP)"
    },
    key: :currency
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      description: "Number of debit entries in the period (camt:052/053 <TtlNtries> DbtNb)"
    },
    key: :total_debit_count
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      description: "Number of credit entries in the period (camt:052/053 <TtlNtries> CdtNb)"
    },
    key: :total_credit_count
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      description:
        "Total debit amount in minor currency units (camt:052/053 <TtlNtries> TtlDbtNtries Amt)"
    },
    key: :total_debit_amount
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      description:
        "Total credit amount in minor currency units (camt:052/053 <TtlNtries> TtlCdtNtries Amt)"
    },
    key: :total_credit_amount
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      description: "Total number of transactions (debit + credit) in the period"
    },
    key: :transaction_count
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: ["pending", "computed", "published"],
      description:
        "Snapshot lifecycle status — pending (queued), computed (aggregates ready), " <>
          "published (sent to downstream / regulatory reporting)"
    },
    key: :status
  )

  open_api_property(
    schema: %Schema{
      type: :boolean,
      description:
        "AML review flag — true when activity patterns exceed FinCEN AML thresholds " <>
          "(31 CFR §1020.320 SAR requirements)"
    },
    key: :flagged_for_review
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "Human-readable description of why this snapshot was flagged for AML review"
    },
    key: :review_reason
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "SAR (Suspicious Activity Report) filing reference (FinCEN SAR form 111)"
    },
    key: :sar_reference
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "Caller-supplied idempotency key (unique per tenant when set)"
    },
    key: :external_reference
  )

  open_api_property(schema: %Schema{type: :string, format: :uuid}, key: :account_holder_id)

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      description: "PaymentAccount scoping this snapshot (camt:052/053 <Acct>)"
    },
    key: :payment_account_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      description: "LedgerAccount scoping this snapshot (chart-of-accounts view)"
    },
    key: :ledger_account_id
  )

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
    title: "AccountActivitySnapshot",
    description:
      "Account activity snapshot — periodic summary of debit/credit activity for an AccountHolder. " <>
        "Maps to ISO 20022 camt:052 (intraday account report) and camt:053 (account statement). " <>
        "AML fields (flagged_for_review, review_reason, sar_reference) support FinCEN SAR filing " <>
        "under 31 CFR §1020.320.",
    required: [
      :snapshot_type,
      :period_start,
      :period_end,
      :account_holder_id,
      :tenant_id
    ],
    properties: [
      :id,
      :snapshot_type,
      :period_start,
      :period_end,
      :opening_balance,
      :closing_balance,
      :currency,
      :total_debit_count,
      :total_credit_count,
      :total_debit_amount,
      :total_credit_amount,
      :transaction_count,
      :status,
      :flagged_for_review,
      :review_reason,
      :sar_reference,
      :external_reference,
      :account_holder_id,
      :payment_account_id,
      :ledger_account_id,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "account_activity_snapshots" do
    field :snapshot_type, Ecto.Enum, values: [:intraday, :daily, :weekly, :monthly]

    field :period_start, :utc_datetime_usec
    field :period_end, :utc_datetime_usec

    field :opening_balance, :integer
    field :closing_balance, :integer
    field :currency, :string

    field :total_debit_count, :integer, default: 0
    field :total_credit_count, :integer, default: 0
    field :total_debit_amount, :integer, default: 0
    field :total_credit_amount, :integer, default: 0
    field :transaction_count, :integer, default: 0

    field :status, Ecto.Enum,
      values: [:pending, :computed, :published],
      default: :pending

    field :flagged_for_review, :boolean, default: false
    field :review_reason, :string
    field :sar_reference, :string
    field :external_reference, :string

    # Relationships
    belongs_to :account_holder, AccountHolder
    belongs_to :payment_account, PaymentAccount
    belongs_to :ledger_account, LedgerAccount

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :snapshot_type,
      :period_start,
      :period_end,
      :opening_balance,
      :closing_balance,
      :currency,
      :review_reason,
      :sar_reference,
      :external_reference,
      :account_holder_id,
      :payment_account_id,
      :ledger_account_id,
      :tenant_id
    ])
    |> maybe_cast_status(attrs)
    |> maybe_cast_with_default(attrs, :total_debit_count, 0)
    |> maybe_cast_with_default(attrs, :total_credit_count, 0)
    |> maybe_cast_with_default(attrs, :total_debit_amount, 0)
    |> maybe_cast_with_default(attrs, :total_credit_amount, 0)
    |> maybe_cast_with_default(attrs, :transaction_count, 0)
    |> maybe_cast_with_default(attrs, :flagged_for_review, false)
    |> validate_required([
      :snapshot_type,
      :period_start,
      :period_end,
      :account_holder_id,
      :tenant_id
    ])
    |> validate_period_order()
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:payment_account_id)
    |> foreign_key_constraint(:ledger_account_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:external_reference, :tenant_id],
      name: :account_activity_snapshots_external_ref_tenant_unique,
      message: "has already been taken"
    )
  end

  # Only cast status when explicitly provided and non-nil.
  # ExOpenApiUtils.Changeset.cast/3 calls Mapper.to_map internally, which includes all struct
  # fields even when nil. Casting nil status would override the Ecto/DB default of :pending.
  defp maybe_cast_status(changeset, attrs) do
    status = Map.get(attrs, :status)

    if is_nil(status) do
      changeset
    else
      Ecto.Changeset.cast(changeset, %{status: status}, [:status])
    end
  end

  # Cast a field only when explicitly provided and non-nil; otherwise use the given default.
  # This prevents ExOpenApiUtils nil values from overriding DB/Ecto defaults.
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

    if period_start && period_end && DateTime.compare(period_start, period_end) == :gt do
      add_error(changeset, :period_end, "must be after period_start")
    else
      changeset
    end
  end
end
