defmodule AtomicFi.LedgerEntryContext.LedgerEntry do
  use AtomicFi.Schema

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.Extensions.Ecto.VelocityLimitArrayType
  alias AtomicFi.LedgerAccountContext.LedgerAccount
  alias AtomicFi.TenantContext.Tenant

  @typedoc """
  LedgerEntry — individual debit/credit line item (ISO 20022 CdtDbtInd).

  Entries are created in balanced pairs (one debit, one credit), each on a leaf
  LedgerAccount, so `Σ debits = Σ credits`. Inserting an entry propagates its
  amount up the ledger-account ancestor chain (running balances and the flat
  `last_*_limit` columns on `ledger_account_balances`) via the
  `ledger_entry_propagate_to_balances` trigger; if a velocity-limit CHECK
  constraint on `ledger_account_balances` fires, the trigger instead persists the
  entry `:voided` and records which account / period / direction / rule
  (the `rejected_*` fields). Voiding an existing entry (status → :voided)
  reverses its balance delta.

  ## Attributes

  * `id` - UUID primary key
  * `account_holder_id` - FK to AccountHolder (MDM subject)
  * `ledger_account_id` - FK to the (leaf) LedgerAccount
  * `currency` - ISO 4217 three-letter code — inherited from LedgerAccount → Ledger
  * `amount` - Amount in minor currency units (>= 0)
  * `entry_type` - ISO 20022 CdtDbtInd: `credit` | `debit`
  * `status` - `pending` | `posted` | `reversed` | `voided`
  * `entry_date` - ISO 20022 ValDt — value/settlement date (nullable)
  * `external_entry_id` - Opaque external SoE ID (nullable; upsert identity)
  * `limits_at_entry` - Velocity limits (rule engine output) for this entry's leaf account — a list of `{period, direction, cap, rule}`; the trigger fans these into `ledger_account_balances.last_*_limit` for every ancestor
  * `rejected_ledger_account_id` - FK to the LedgerAccount whose velocity limit was breached (NULL unless `:voided` for a limit)
  * `rejected_period` - `"daily" | "weekly" | "monthly" | "yearly"` (NULL unless rejected)
  * `rejected_direction` - `"debit" | "credit"` (NULL unless rejected)
  * `rejected_rule` - the rule that set the breached cap (NULL unless rejected)
  * `rejected_code` - e.g. `"LIMIT_EXCEEDED"` (NULL unless rejected)
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
             :status,
             :rejected_ledger_account_id
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
      description: "ISO 4217 three-letter currency code — inherited from LedgerAccount → Ledger."
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
      type: :array,
      nullable: true,
      items: %Schema{
        type: :object,
        properties: %{
          period: %Schema{type: :string, enum: ["daily", "weekly", "monthly", "yearly"]},
          direction: %Schema{type: :string, enum: ["debit", "credit"]},
          cap: %Schema{
            type: :integer,
            nullable: true,
            description: "Minor units; null = unconstrained"
          },
          rule: %Schema{type: :string, nullable: true}
        }
      },
      description:
        "Velocity limits (rule engine output) for this entry's leaf account. The trigger fans " <>
          "these into ledger_account_balances.last_*_limit on every ancestor."
    },
    key: :limits_at_entry
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      readOnly: true,
      description: "LedgerAccount whose velocity limit was breached (NULL unless rejected)."
    },
    key: :rejected_ledger_account_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      readOnly: true,
      enum: ["daily", "weekly", "monthly", "yearly"]
    },
    key: :rejected_period
  )

  open_api_property(
    schema: %Schema{type: :string, nullable: true, readOnly: true, enum: ["debit", "credit"]},
    key: :rejected_direction
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      readOnly: true,
      description: "Rule that set the breached cap."
    },
    key: :rejected_rule
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      readOnly: true,
      description: "e.g. LIMIT_EXCEEDED."
    },
    key: :rejected_code
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
      "Debit/credit line item (ISO 20022 CdtDbtInd) on a leaf LedgerAccount. Created in balanced " <>
        "pairs (Σ debits = Σ credits). The propagate trigger rolls the amount + the entry's velocity " <>
        "limits up the ledger-account ancestor chain; a breached limit CHECK persists the entry " <>
        ":voided with the rejected_* details.",
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
      :limits_at_entry,
      :rejected_ledger_account_id,
      :rejected_period,
      :rejected_direction,
      :rejected_rule,
      :rejected_code,
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

    # Velocity limits (rule engine output) for this entry's leaf account. The trigger
    # fans these into ledger_account_balances.last_*_limit on every ancestor.
    field :limits_at_entry, VelocityLimitArrayType, default: []

    # Set by the trigger when the entry is persisted :voided because a velocity-limit
    # CHECK constraint on ledger_account_balances fired. NULL when posted normally.
    belongs_to :rejected_ledger_account, LedgerAccount, foreign_key: :rejected_ledger_account_id
    field :rejected_period, :string
    field :rejected_direction, :string
    field :rejected_rule, :string
    field :rejected_code, :string

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
      :limits_at_entry,
      :rejected_ledger_account_id,
      :rejected_period,
      :rejected_direction,
      :rejected_rule,
      :rejected_code,
      :tenant_id
      # rejected_* are readOnly in the API (clients can't set them); the propagate
      # trigger sets them on a limit breach, and create_entries copies them onto the
      # paired entry when voiding both.
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
    |> foreign_key_constraint(:rejected_ledger_account_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint(:external_entry_id, name: :ledger_entries_external_entry_id_unique)
  end
end
