defmodule PaymentCompliancePlatform.LedgerEntryContext.LedgerEntry do
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.AccountHolderContext.AccountHolder
  alias PaymentCompliancePlatform.LedgerAccountContext.LedgerAccount
  alias PaymentCompliancePlatform.TenantContext.Tenant

  @typedoc """
  LedgerEntry — individual debit/credit line item (ISO 20022 CdtDbtInd).

  Creating a credit entry atomically increments the parent LedgerAccount.balance.
  Creating a debit entry atomically decrements the parent LedgerAccount.balance.
  Voiding an entry (status → :voided) atomically reverses the balance delta via
  the `ledger_entry_propagate_to_balances` PostgreSQL trigger.

  ## Attributes

  * `id` - UUID primary key
  * `account_holder_id` - FK to AccountHolder (MDM subject)
  * `ledger_account_id` - FK to parent LedgerAccount
  * `currency` - ISO 4217 three-letter code — inherited from parent LedgerAccount → Ledger
  * `amount` - Amount in minor currency units (>= 0)
  * `entry_type` - ISO 20022 CdtDbtInd: `credit` | `debit`
  * `status` - `pending` | `posted` | `reversed` | `voided`
  * `entry_date` - ISO 20022 ValDt — value/settlement date (nullable)
  * `external_entry_id` - Opaque external SoE ID (nullable; upsert identity)
  * `daily_debit_limit_at_entry` / `daily_credit_limit_at_entry` - Velocity limits at entry time (risk engine snapshot)
  * `weekly_debit_limit_at_entry` / `weekly_credit_limit_at_entry` - Week velocity limits
  * `monthly_debit_limit_at_entry` / `monthly_credit_limit_at_entry` - Month velocity limits
  * `yearly_debit_limit_at_entry` / `yearly_credit_limit_at_entry` - Year velocity limits
  * `tenant_id` - FK to tenant for RLS
  * `inserted_at`, `updated_at` - Timestamps
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Flop.Schema,
           filterable: [
             :id,
             :tenant_id,
             :account_holder_id,
             :ledger_account_id,
             :entry_type,
             :status
           ],
           sortable: [:id, :inserted_at, :updated_at, :entry_type, :status, :entry_date, :amount],
           default_limit: 20,
           max_limit: 100}

  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{type: :string, format: :uuid},
    key: :account_holder_id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid},
    key: :ledger_account_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      description:
        "ISO 4217 three-letter currency code — inherited from parent LedgerAccount → Ledger."
    },
    key: :currency
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      description: "Amount in minor currency units (e.g. cents for USD). Must be >= 0."
    },
    key: :amount
  )

  open_api_property(
    schema: %Schema{type: :string, enum: ["credit", "debit"]},
    key: :entry_type
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: ["pending", "posted", "reversed", "voided"]
    },
    key: :status
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :date,
      nullable: true,
      description: "ISO 20022 ValDt — value/settlement date"
    },
    key: :entry_date
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "Opaque external SoE identifier (upsert identity)"
    },
    key: :external_entry_id
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      description:
        "Daily debit velocity limit at entry creation time (minor currency units). " <>
          "Supplied by risk engine via orchestration layer. NULL = unconstrained. " <>
          "Trigger copies this to ledger_account_balances.last_daily_debit_limit."
    },
    key: :daily_debit_limit_at_entry
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      description: "Daily credit velocity limit at entry creation time. NULL = unconstrained."
    },
    key: :daily_credit_limit_at_entry
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      description: "Weekly debit velocity limit at entry creation time. NULL = unconstrained."
    },
    key: :weekly_debit_limit_at_entry
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      description: "Weekly credit velocity limit at entry creation time. NULL = unconstrained."
    },
    key: :weekly_credit_limit_at_entry
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      description: "Monthly debit velocity limit at entry creation time. NULL = unconstrained."
    },
    key: :monthly_debit_limit_at_entry
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      description: "Monthly credit velocity limit at entry creation time. NULL = unconstrained."
    },
    key: :monthly_credit_limit_at_entry
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      description: "Yearly debit velocity limit at entry creation time. NULL = unconstrained."
    },
    key: :yearly_debit_limit_at_entry
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      description: "Yearly credit velocity limit at entry creation time. NULL = unconstrained."
    },
    key: :yearly_credit_limit_at_entry
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
    title: "LedgerEntry",
    description:
      "Individual debit/credit line item (ISO 20022 CdtDbtInd). " <>
        "Creating an entry atomically updates the parent LedgerAccount balance via DB trigger. " <>
        "Voiding an entry (status → voided) atomically reverses the balance delta. " <>
        "Velocity limit snapshots (*_limit_at_entry) are set by the orchestration layer from the risk engine " <>
        "and are propagated by the trigger to ledger_account_balances.last_*_limit for CHECK constraint enforcement.",
    required: [:account_holder_id, :ledger_account_id, :currency, :amount, :entry_type],
    properties: [
      :id,
      :account_holder_id,
      :ledger_account_id,
      :currency,
      :amount,
      :entry_type,
      :status,
      :entry_date,
      :external_entry_id,
      :daily_debit_limit_at_entry,
      :daily_credit_limit_at_entry,
      :weekly_debit_limit_at_entry,
      :weekly_credit_limit_at_entry,
      :monthly_debit_limit_at_entry,
      :monthly_credit_limit_at_entry,
      :yearly_debit_limit_at_entry,
      :yearly_credit_limit_at_entry,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "ledger_entries" do
    belongs_to :account_holder, AccountHolder
    belongs_to :ledger_account, LedgerAccount

    field :currency, :string
    field :amount, :integer

    field :entry_type, Ecto.Enum, values: [:credit, :debit]

    field :status, Ecto.Enum,
      values: [:pending, :posted, :reversed, :voided],
      default: :pending

    field :entry_date, :date
    field :external_entry_id, :string

    # Velocity limit snapshots (set by orchestration layer from risk engine at entry creation time)
    # The trigger reads these and copies them to ledger_account_balances.last_*_limit so
    # CHECK constraints enforce velocity limits correctly. NULL = unconstrained.
    field :daily_debit_limit_at_entry, :integer
    field :daily_credit_limit_at_entry, :integer
    field :weekly_debit_limit_at_entry, :integer
    field :weekly_credit_limit_at_entry, :integer
    field :monthly_debit_limit_at_entry, :integer
    field :monthly_credit_limit_at_entry, :integer
    field :yearly_debit_limit_at_entry, :integer
    field :yearly_credit_limit_at_entry, :integer

    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(ledger_entry, attrs) do
    ledger_entry
    |> cast(attrs, [
      :account_holder_id,
      :ledger_account_id,
      :currency,
      :amount,
      :entry_type,
      :status,
      :entry_date,
      :external_entry_id,
      :daily_debit_limit_at_entry,
      :daily_credit_limit_at_entry,
      :weekly_debit_limit_at_entry,
      :weekly_credit_limit_at_entry,
      :monthly_debit_limit_at_entry,
      :monthly_credit_limit_at_entry,
      :yearly_debit_limit_at_entry,
      :yearly_credit_limit_at_entry,
      :tenant_id
    ])
    |> validate_required([
      :account_holder_id,
      :ledger_account_id,
      :currency,
      :amount,
      :entry_type,
      :tenant_id
    ])
    |> validate_length(:currency, is: 3)
    |> validate_number(:amount, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:ledger_account_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint(:external_entry_id, name: :ledger_entries_external_entry_id_unique)
  end
end
