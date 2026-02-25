defmodule PaymentCompliancePlatform.LedgerAccountContext.LedgerAccountBalance do
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.LedgerAccountContext.LedgerAccount
  alias PaymentCompliancePlatform.TenantContext.Tenant

  @typedoc """
  LedgerAccountBalance — daily balance snapshot for a LedgerAccount.

  One row per (ledger_account_id, balance_date). Rows are created and updated
  entirely by the `ledger_entry_propagate_to_balances` PostgreSQL trigger —
  never by application code directly.

  Each row carries:
  - `daily_debit` / `daily_credit` — amounts debited/credited on this calendar day
  - `weekly_debit` / `weekly_credit` — week-to-date cumulative totals (iso_week + year)
  - `monthly_debit` / `monthly_credit` — month-to-date cumulative totals
  - `yearly_debit` / `yearly_credit` — year-to-date cumulative totals
  - `last_*_limit` — most recent velocity limits from the risk engine (propagated
    from ledger_entry.*_limit_at_entry). Used by DB CHECK constraints.

  Velocity limit enforcement is entirely DB-driven:
      CHECK (last_daily_debit_limit IS NULL OR daily_debit <= last_daily_debit_limit)
  The application never enforces limits directly.

  Past rows (prior days/weeks/months) are immutable historical audit data.

  ## Attributes

  * `id` - UUID primary key
  * `ledger_account_id` - FK to LedgerAccount
  * `tenant_id` - FK to tenant for RLS
  * `balance_date` - Calendar date for this snapshot
  * `iso_week` - ISO week number (1–53)
  * `month` - Calendar month (1–12)
  * `year` - Calendar year (e.g. 2026)
  * `daily_debit` / `daily_credit` - Debits/credits on this day (minor currency units)
  * `weekly_debit` / `weekly_credit` - Week-to-date cumulative
  * `monthly_debit` / `monthly_credit` - Month-to-date cumulative
  * `yearly_debit` / `yearly_credit` - Year-to-date cumulative
  * `last_*_limit` - Most recent limits from risk engine (NULL = unconstrained)
  * `inserted_at`, `updated_at` - Timestamps
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Flop.Schema,
           filterable: [
             :id,
             :tenant_id,
             :ledger_account_id,
             :balance_date,
             :iso_week,
             :month,
             :year
           ],
           sortable: [:balance_date, :inserted_at, :updated_at],
           default_limit: 20,
           max_limit: 100}

  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{type: :string, format: :uuid},
    key: :ledger_account_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :date,
      readOnly: true,
      description: "Calendar date for this snapshot"
    },
    key: :balance_date
  )

  open_api_property(
    schema: %Schema{type: :integer, readOnly: true, description: "ISO week number (1–53)"},
    key: :iso_week
  )

  open_api_property(
    schema: %Schema{type: :integer, readOnly: true, description: "Calendar month (1–12)"},
    key: :month
  )

  open_api_property(
    schema: %Schema{type: :integer, readOnly: true, description: "Calendar year"},
    key: :year
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      readOnly: true,
      description: "Total debits on this calendar day (minor currency units). Trigger-maintained."
    },
    key: :daily_debit
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      readOnly: true,
      description:
        "Total credits on this calendar day (minor currency units). Trigger-maintained."
    },
    key: :daily_credit
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      readOnly: true,
      description: "Week-to-date cumulative debits (minor currency units). Trigger-maintained."
    },
    key: :weekly_debit
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      readOnly: true,
      description: "Week-to-date cumulative credits (minor currency units). Trigger-maintained."
    },
    key: :weekly_credit
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      readOnly: true,
      description: "Month-to-date cumulative debits (minor currency units). Trigger-maintained."
    },
    key: :monthly_debit
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      readOnly: true,
      description: "Month-to-date cumulative credits (minor currency units). Trigger-maintained."
    },
    key: :monthly_credit
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      readOnly: true,
      description: "Year-to-date cumulative debits (minor currency units). Trigger-maintained."
    },
    key: :yearly_debit
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      readOnly: true,
      description: "Year-to-date cumulative credits (minor currency units). Trigger-maintained."
    },
    key: :yearly_credit
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      readOnly: true,
      description:
        "Last known daily debit limit from risk engine (minor currency units). " <>
          "NULL = unconstrained. Enforced by DB CHECK constraint. Trigger-maintained."
    },
    key: :last_daily_debit_limit
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      readOnly: true,
      description: "Last known daily credit limit from risk engine. NULL = unconstrained."
    },
    key: :last_daily_credit_limit
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      readOnly: true,
      description: "Last known weekly debit limit from risk engine. NULL = unconstrained."
    },
    key: :last_weekly_debit_limit
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      readOnly: true,
      description: "Last known weekly credit limit from risk engine. NULL = unconstrained."
    },
    key: :last_weekly_credit_limit
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      readOnly: true,
      description: "Last known monthly debit limit from risk engine. NULL = unconstrained."
    },
    key: :last_monthly_debit_limit
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      readOnly: true,
      description: "Last known monthly credit limit from risk engine. NULL = unconstrained."
    },
    key: :last_monthly_credit_limit
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      readOnly: true,
      description: "Last known yearly debit limit from risk engine. NULL = unconstrained."
    },
    key: :last_yearly_debit_limit
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      readOnly: true,
      description: "Last known yearly credit limit from risk engine. NULL = unconstrained."
    },
    key: :last_yearly_credit_limit
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
    title: "LedgerAccountBalance",
    description:
      "Daily balance snapshot for a LedgerAccount. " <>
        "Created and updated entirely by the ledger_entry_propagate_to_balances trigger. " <>
        "Each row carries day/week/month/year cumulative totals and last known risk engine limits. " <>
        "Velocity limits are enforced via DB CHECK constraints on last_*_limit columns.",
    required: [:ledger_account_id],
    properties: [
      :id,
      :ledger_account_id,
      :balance_date,
      :iso_week,
      :month,
      :year,
      :daily_debit,
      :daily_credit,
      :weekly_debit,
      :weekly_credit,
      :monthly_debit,
      :monthly_credit,
      :yearly_debit,
      :yearly_credit,
      :last_daily_debit_limit,
      :last_daily_credit_limit,
      :last_weekly_debit_limit,
      :last_weekly_credit_limit,
      :last_monthly_debit_limit,
      :last_monthly_credit_limit,
      :last_yearly_debit_limit,
      :last_yearly_credit_limit,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "ledger_account_balances" do
    belongs_to :ledger_account, LedgerAccount

    field :balance_date, :date
    field :iso_week, :integer
    field :month, :integer
    field :year, :integer

    # Period running balances (trigger-maintained)
    field :daily_debit, :integer, default: 0
    field :daily_credit, :integer, default: 0
    field :weekly_debit, :integer, default: 0
    field :weekly_credit, :integer, default: 0
    field :monthly_debit, :integer, default: 0
    field :monthly_credit, :integer, default: 0
    field :yearly_debit, :integer, default: 0
    field :yearly_credit, :integer, default: 0

    # Last known limits from risk engine (trigger-maintained from entry snapshots)
    field :last_daily_debit_limit, :integer
    field :last_daily_credit_limit, :integer
    field :last_weekly_debit_limit, :integer
    field :last_weekly_credit_limit, :integer
    field :last_monthly_debit_limit, :integer
    field :last_monthly_credit_limit, :integer
    field :last_yearly_debit_limit, :integer
    field :last_yearly_credit_limit, :integer

    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end
end
