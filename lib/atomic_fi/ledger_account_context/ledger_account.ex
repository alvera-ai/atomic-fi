defmodule AtomicFi.LedgerAccountContext.LedgerAccount do
  use AtomicFi.Schema

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.LedgerContext.Ledger
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  alias AtomicFi.TenantContext.Tenant

  @typedoc """
  LedgerAccount — a control account in the double-entry payments ledger.

  All ledger accounts are zero-target control accounts; the meaningful split is
  the *normal balance* — `side` `:credit` (credit-normal, like a liability) or
  `:debit` (debit-normal, like an asset). `balance` is the running net
  (credits − debits), maintained atomically by the `ledger_entry_propagate_to_balances`
  trigger on ledger entry INSERT / status→voided.

  Hierarchy: a Ledger (one per AccountHolder per currency) holds two master roots
  (one per `side`, no `payment_account_id` / `counterparty_id`); a PaymentAccount
  gets a side-account under the matching master root, and one leaf per regulatory
  regime under that. `ancestor_ids` materializes the root-first ancestor path for
  O(1) roll-up by the trigger. `regime` is a generic discriminator (regulatory
  regime, fraud regime, …) — the leaves carry the real regime; structural nodes
  carry a sentinel set by the orchestration layer.

  Velocity limits themselves live on `ledger_account_balances.limits`
  (`velocity_limit[]`), kept up to date by the trigger from
  `ledger_entries.limits_at_entry`. The limit *check* is performed in Elixir
  when ledger entries are created, not by the database.

  ## Attributes

  * `id` - UUID primary key
  * `account_holder_id` - FK to AccountHolder (MDM subject)
  * `ledger_id` - FK to parent Ledger (chart-of-accounts container; one per (AH, currency))
  * `currency` - ISO 4217 three-letter code — inherited from parent Ledger
  * `side` - Normal balance: `credit` (credit-normal) | `debit` (debit-normal)
  * `regime` - Generic regime discriminator (regulatory / fraud / …); leaves carry the real regime, structural nodes a sentinel
  * `status` - LedgerAccount lifecycle: `active` | `closed`
  * `balance` - Running net (credits − debits) in minor currency units (trigger-maintained, readOnly in API)
  * `ledger_account_number` - Opaque external SoE ID (nullable; upsert identity)
  * `parent_ledger_account_id` - FK to parent LedgerAccount (nullable — master roots have no parent)
  * `payment_account_id` - FK to PaymentAccount (nullable — set on PaymentAccount side-accounts and their regime leaves)
  * `counterparty_id` - FK to Counterparty (nullable — set on Counterparty accounts and their regime leaves)
  * `ancestor_ids` - Materialized flat list of all ancestor account UUIDs, root-first (system-maintained)
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
             :side,
             :regime,
             :status,
             :parent_ledger_account_id,
             :payment_account_id,
             :counterparty_id
           ],
           sortable: [:id, :inserted_at, :updated_at, :side, :status, :balance],
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
      enum: ["credit", "debit"],
      description: "Normal balance: credit (credit-normal) or debit (debit-normal)."
    },
    key: :side
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      description:
        "Generic regime discriminator (regulatory regime, fraud regime, …). " <>
          "Regime leaves carry the real regime name; structural nodes carry a sentinel."
    },
    key: :regime
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
        "Running net balance (credits − debits) in minor currency units. " <>
          "Atomically maintained by the ledger_entry_propagate_to_balances trigger on entry insert/void."
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
      description: "Parent LedgerAccount UUID. NULL = master root account."
    },
    key: :parent_ledger_account_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      description: "PaymentAccount this account belongs to (NULL on master roots)."
    },
    key: :payment_account_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      description:
        "Counterparty this account belongs to (NULL on master roots and PaymentAccount accounts)."
    },
    key: :counterparty_id
  )

  open_api_property(
    schema: %Schema{
      type: :array,
      items: %Schema{type: :string, format: :uuid},
      readOnly: true,
      description:
        "Materialized flat list of all ancestor account UUIDs (root-first order). " <>
          "System-maintained. Used by the trigger for O(1) ancestor balance propagation."
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
      "Control account in the double-entry payments ledger. `side` is the normal balance " <>
        "(credit-normal | debit-normal); `balance` is the running net (credits − debits), " <>
        "trigger-maintained. Self-referential hierarchy via parent_ledger_account_id / ancestor_ids; " <>
        "regime is a generic discriminator. Velocity limits live on ledger_account_balances.limits.",
    required: [:account_holder_id, :ledger_id, :currency, :side, :regime],
    properties: [
      :id,
      :account_holder_id,
      :ledger_id,
      :currency,
      :side,
      :regime,
      :status,
      :balance,
      :ledger_account_number,
      :parent_ledger_account_id,
      :payment_account_id,
      :counterparty_id,
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

    field :side, Ecto.Enum, values: [:credit, :debit]
    field :regime, :string

    field :status, Ecto.Enum,
      values: [:active, :closed],
      default: :active

    # Running net (credits − debits) in minor units — maintained atomically by trigger.
    # NEVER writable via the API changeset.
    field :balance, :integer, default: 0

    field :ledger_account_number, :string

    # ── Hierarchy ────────────────────────────────────────────────────────────
    # Self-referential parent (nullable — master roots have no parent)
    belongs_to :parent_ledger_account, __MODULE__, foreign_key: :parent_ledger_account_id

    # Entity this account belongs to (exactly one set, or neither on master roots)
    belongs_to :payment_account, PaymentAccount, foreign_key: :payment_account_id
    belongs_to :counterparty, Counterparty, foreign_key: :counterparty_id

    # Materialized ancestor path (root-first) — populated by context at write time.
    # System-maintained — excluded from API changeset cast.
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
      :side,
      :regime,
      :status,
      :ledger_account_number,
      :parent_ledger_account_id,
      :payment_account_id,
      :counterparty_id,
      :tenant_id
      # NOTE: :balance intentionally excluded — never writable via API
      # NOTE: :ancestor_ids intentionally excluded — system-maintained by context
    ])
    |> validate_required([
      :account_holder_id,
      :ledger_id,
      :currency,
      :side,
      :regime,
      :tenant_id
    ])
    |> validate_length(:currency, is: 3)
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:ledger_id)
    |> foreign_key_constraint(:parent_ledger_account_id)
    |> foreign_key_constraint(:payment_account_id)
    |> foreign_key_constraint(:counterparty_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:ledger_id, :side, :regime],
      name: :ledger_accounts_ledger_side_regime_master_unique
    )
    |> unique_constraint([:ledger_id, :side, :payment_account_id, :regime],
      name: :ledger_accounts_ledger_side_pa_regime_unique
    )
    |> unique_constraint([:ledger_id, :side, :counterparty_id, :regime],
      name: :ledger_accounts_ledger_side_cp_regime_unique
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
