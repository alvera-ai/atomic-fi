defmodule PaymentCompliancePlatform.LedgerAccountContext.LedgerAccount do
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.AccountHolderContext.AccountHolder
  alias PaymentCompliancePlatform.LedgerContext.Ledger
  alias PaymentCompliancePlatform.TenantContext.Tenant

  @typedoc """
  LedgerAccount — chart-of-accounts line item within a Ledger.

  Stores a running balance in minor currency units (e.g. cents for USD).
  Balance is atomically updated by the ledger_entry_propagate_to_balances trigger
  on ledger_entry INSERT or UPDATE (status → voided).

  Velocity limits are NOT stored here — they are managed by the risk engine and
  stored on ledger_account_balances rows (populated by the trigger from
  ledger_entry.*_limit_at_entry snapshots).

  In application code, convert to Money for display/arithmetic:
      Money.new!(account.balance, account.currency)

  LedgerAccounts are hierarchical: a Counterparty gets a root LedgerAccount;
  PaymentAccounts under a Counterparty get child LedgerAccounts. All ancestor
  UUIDs are materialized in ancestor_ids for O(1) lookup. A no-cycle guard
  ensures the hierarchy remains a valid tree.

  ## Attributes

  * `id` - UUID primary key
  * `account_holder_id` - FK to AccountHolder (MDM subject)
  * `ledger_id` - FK to parent Ledger (chart-of-accounts container)
  * `currency` - ISO 4217 three-letter code — inherited from parent Ledger
  * `account_type` - GAAP classification: `asset` | `liability` | `equity` | `revenue` | `expense`
  * `status` - LedgerAccount lifecycle: `active` | `closed`
  * `balance` - Running balance in minor currency units (trigger-maintained, readOnly in API)
  * `ledger_account_number` - Opaque external SoE ID (nullable; upsert identity)
  * `parent_ledger_account_id` - FK to parent LedgerAccount (nullable — root has no parent)
  * `ancestor_ids` - Materialized flat list of all ancestor account UUIDs (system-maintained)
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
             :ledger_id,
             :account_type,
             :status,
             :parent_ledger_account_id
           ],
           sortable: [:id, :inserted_at, :updated_at, :account_type, :status, :balance],
           default_limit: 20,
           max_limit: 100}

  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{type: :string, format: :uuid},
    key: :account_holder_id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid},
    key: :ledger_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      description: "ISO 4217 three-letter currency code — inherited from parent Ledger."
    },
    key: :currency
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: ["asset", "liability", "equity", "revenue", "expense"]
    },
    key: :account_type
  )

  open_api_property(
    schema: %Schema{type: :string, nullable: true, enum: ["active", "closed"]},
    key: :status
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      readOnly: true,
      description:
        "Running balance in minor currency units (e.g. cents for USD). " <>
          "Atomically updated by the ledger_entry_propagate_to_balances trigger on entry insert/void. " <>
          "Convert to Money: Money.new!(account.balance, account.currency)"
    },
    key: :balance
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "Opaque external SoE identifier (upsert identity)"
    },
    key: :ledger_account_number
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      description:
        "Parent LedgerAccount UUID. NULL = root account. " <>
          "Counterparty root accounts have no parent; PaymentAccounts created under a " <>
          "Counterparty have the Counterparty's LedgerAccount as parent."
    },
    key: :parent_ledger_account_id
  )

  open_api_property(
    schema: %Schema{
      type: :array,
      items: %Schema{type: :string, format: :uuid},
      readOnly: true,
      description:
        "Materialized flat list of all ancestor account UUIDs (root-first order). " <>
          "System-maintained — populated by the context on create/update. " <>
          "Used by the trigger for O(1) ancestor balance propagation."
    },
    key: :ancestor_ids
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
    title: "LedgerAccount",
    description:
      "Chart-of-accounts line item within a Ledger (ISO 20022 camt:052/camt:053). " <>
        "Stores a running balance updated atomically by the entry propagation trigger. " <>
        "Supports self-referential hierarchy via parent_ledger_account_id and ancestor_ids. " <>
        "Velocity limits are enforced on ledger_account_balances (managed by risk engine).",
    required: [:account_holder_id, :ledger_id, :currency, :account_type],
    properties: [
      :id,
      :account_holder_id,
      :ledger_id,
      :currency,
      :account_type,
      :status,
      :balance,
      :ledger_account_number,
      :parent_ledger_account_id,
      :ancestor_ids,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "ledger_accounts" do
    belongs_to :account_holder, AccountHolder
    belongs_to :ledger, Ledger

    field :currency, :string

    field :account_type, Ecto.Enum,
      values: [:asset, :liability, :equity, :revenue, :expense],
      default: :asset

    field :status, Ecto.Enum,
      values: [:active, :closed],
      default: :active

    # Running balance in minor units — maintained atomically by trigger
    # NEVER writable via the API changeset
    field :balance, :integer, default: 0

    field :ledger_account_number, :string

    # ── Hierarchy ────────────────────────────────────────────────────────────
    # Self-referential parent (nullable — root accounts have no parent)
    belongs_to :parent_ledger_account, __MODULE__, foreign_key: :parent_ledger_account_id

    # Materialized ancestor path — populated by context at write time
    # System-maintained — excluded from API changeset cast
    field :ancestor_ids, {:array, :binary_id}, default: []

    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(ledger_account, attrs) do
    ledger_account
    |> cast(attrs, [
      :account_holder_id,
      :ledger_id,
      :currency,
      :account_type,
      :status,
      :ledger_account_number,
      :parent_ledger_account_id,
      :tenant_id
      # NOTE: :balance intentionally excluded — never writable via API
      # NOTE: :ancestor_ids intentionally excluded — system-maintained by context
    ])
    |> validate_required([:account_holder_id, :ledger_id, :currency, :account_type, :tenant_id])
    |> validate_length(:currency, is: 3)
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:ledger_id)
    |> foreign_key_constraint(:parent_ledger_account_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:ledger_id, :account_type],
      name: :ledger_accounts_ledger_id_account_type_index
    )
    |> unique_constraint(:ledger_account_number,
      name: :ledger_accounts_ledger_account_number_unique
    )
    |> validate_no_ancestor_cycle()
  end

  # Ensures this account is not its own ancestor (prevents cycles in the hierarchy tree).
  # The context populates ancestor_ids before calling changeset, so this validation
  # catches any attempt to create a circular parent reference.
  defp validate_no_ancestor_cycle(changeset) do
    id = get_field(changeset, :id)
    ancestor_ids = get_field(changeset, :ancestor_ids) || []

    if id && id in ancestor_ids do
      add_error(changeset, :ancestor_ids, "cycle detected — account cannot be its own ancestor")
    else
      changeset
    end
  end
end
