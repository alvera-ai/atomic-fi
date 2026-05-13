defmodule AtomicFi.LedgerAccountContext.LedgerAccount do
  use AtomicFi.Schema

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.LedgerAccountContext.LinkedLedgerAccount
  alias AtomicFi.LedgerContext.Ledger
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  alias AtomicFi.TenantContext.Tenant

  # Sentinel regime name for an aggregation-root row (the catch-all bucket
  # for a (pa, cp) tuple). Children carry the actual regime name (e.g. "ach").
  @root_regime "root"

  @la_types [
    :counter_party_root,
    :counter_party_regime_root,
    :account_holder_payment_account_root,
    :account_holder_payment_account_regime_root,
    :counter_party_payment_account_root,
    :counter_party_payment_account_regime_root
  ]

  @doc "Returns the sentinel regime name for aggregation-root rows."
  @spec root_regime() :: String.t()
  def root_regime, do: @root_regime

  @doc "List of valid `la_type` enum values."
  @spec la_types() :: [atom()]
  def la_types, do: @la_types

  @typedoc """
  LedgerAccount — a control account in the double-entry payments ledger.

  All ledger accounts are zero-target control accounts; each tracks **both** a
  cumulative credit and a cumulative debit balance per period (on the linked
  `ledger_account_balances` rows). `balance` is the running net (credits − debits),
  maintained atomically by the `ledger_entry_propagate_to_balances` trigger on
  ledger entry INSERT / status→voided.

  Hierarchy (one tree per Ledger, i.e. per AccountHolder per currency):

      AH root LA  (regime "_root", no payment_account_id / counterparty_id)
        └─ PaymentAccount "all"-regime LA   (payment_account_id set, regime "all")
             └─ PaymentAccount regime-leaf LAs   (payment_account_id set, regime e.g. "ach_de_minimis")
        └─ Counterparty LA per currency …  (counterparty_id set)

  Ledger entries only ever land on leaf LAs; `ancestor_ids` materializes the
  root-first ancestor path for O(1) roll-up by the trigger. `regime` is a generic
  discriminator (regulatory regime, fraud regime, …) — the leaves carry the real
  regime, structural nodes a sentinel (`"_root"`, `"all"`) set by the
  orchestration layer.

  Velocity limits live on `ledger_entries.limits_at_entry` (`velocity_limit[]`,
  the rule-engine output for the leaf), which the trigger fans up into the flat
  `ledger_account_balances.last_*_limit` columns where the CHECK constraints
  enforce them.

  ## Attributes

  * `id` - UUID primary key
  * `account_holder_id` - FK to AccountHolder (MDM subject)
  * `ledger_id` - FK to parent Ledger (chart-of-accounts container; one per (AH, currency))
  * `currency` - ISO 4217 three-letter code — inherited from parent Ledger
  * `regime` - Generic regime discriminator (regulatory / fraud / …); leaves carry the real regime, structural nodes a sentinel (`"_root"`, `"all"`)
  * `status` - LedgerAccount lifecycle: `active` | `closed`
  * `balance` - Running net (credits − debits) in minor currency units (trigger-maintained, readOnly in API)
  * `ledger_account_number` - Opaque external SoE ID (nullable; upsert identity)
  * `payment_account_id` - FK to PaymentAccount (nullable — set on a PaymentAccount's "all"-regime LA and its regime leaves)
  * `counterparty_id` - FK to Counterparty (nullable — set on Counterparty LAs)
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
             :regime,
             :status,
             :payment_account_id,
             :counterparty_id
           ],
           sortable: [:id, :inserted_at, :updated_at, :regime, :status, :balance],
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
      description:
        "Generic regime discriminator (regulatory regime, fraud regime, …). " <>
          "Regime leaves carry the real regime name; aggregation roots carry the sentinel \"root\"."
    },
    key: :regime
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      enum: [
        "counter_party_root",
        "counter_party_regime_root",
        "account_holder_payment_account_root",
        "account_holder_payment_account_regime_root",
        "counter_party_payment_account_root",
        "counter_party_payment_account_regime_root"
      ],
      description:
        "Position of this row in the LedgerAccount tree. Combined with regime, " <>
          "determines whether this row is an aggregation root or a regime-specific child. " <>
          "Enforced by the ledger_accounts_la_type_shape_check CHECK constraint."
    },
    key: :la_type
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
      items: %OpenApiSpex.Reference{"$ref": "#/components/schemas/LinkedLedgerAccountResponse"},
      readOnly: true,
      description:
        "Read-only edge list — every related LedgerAccount (ancestor or descendant), " <>
          "with the edge `type` indicating direction. Populated automatically by a database " <>
          "trigger on LedgerAccount insert; never written by application code."
    },
    key: :linked_ledger_accounts
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
        "trigger-maintained. Hierarchy is captured solely in the flat ancestor_ids array; " <>
        "regime is a generic discriminator. Velocity limits live on ledger_account_balances.limits.",
    required: [:account_holder_id, :ledger_id, :currency, :regime],
    properties: [
      :id,
      :account_holder_id,
      :ledger_id,
      :currency,
      :regime,
      :status,
      :balance,
      :ledger_account_number,
      :payment_account_id,
      :counterparty_id,
      :la_type,
      :linked_ledger_accounts,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "ledger_accounts" do
    belongs_to :account_holder, AccountHolder
    belongs_to :ledger, Ledger

    field :currency, :string

    field :regime, :string

    field :status, Ecto.Enum,
      values: [:active, :closed],
      default: :active

    # Running net (credits − debits) in minor units — maintained atomically by trigger.
    # NEVER writable via the API changeset.
    field :balance, :integer, default: 0

    field :ledger_account_number, :string

    # ── Tree position ────────────────────────────────────────────────────────
    # Distinguishes the 6 row shapes in the (pa, cp, regime) cross. A DB
    # CHECK constraint (ledger_accounts_la_type_shape_check) enforces
    # consistency between la_type and (payment_account_id, counterparty_id,
    # regime). Required on every insert.
    field :la_type, Ecto.Enum, values: @la_types

    # Cached flat ancestor path (root-first). Single source of truth for
    # tree traversal. Populated by the `ledger_accounts_resolve_ancestor_ids`
    # BEFORE INSERT/UPDATE trigger on the database side, which fails fast
    # (SQLSTATE 23514) if any required ancestor row is missing — Elixir
    # surfaces that failure as a `%Changeset{}` via `check_constraint/3`.
    field :ancestor_ids, {:array, :binary_id}, default: [], read_after_writes: true

    # Cached flat list of every descendant LA. Maintained by the
    # `ledger_accounts_propagate_descendant_id` AFTER INSERT trigger
    # (refreshes the linked_ledger_accounts edge rows too).
    field :descendant_ids, {:array, :binary_id}, default: [], read_after_writes: true

    # Read-side edge list (denormalised twin of ancestor_ids/descendant_ids)
    # for idiomatic Ecto preloads:
    #
    #     Repo.preload(la, linked_ledger_accounts: :to)
    #
    # — yields every related LedgerAccount with edge `type` available.
    has_many :linked_ledger_accounts, LinkedLedgerAccount, foreign_key: :from_ledger_account_id

    # Entity this account belongs to (exactly one set, or neither on master roots)
    belongs_to :payment_account, PaymentAccount, foreign_key: :payment_account_id
    belongs_to :counterparty, Counterparty, foreign_key: :counterparty_id

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
      :regime,
      :status,
      :ledger_account_number,
      :payment_account_id,
      :counterparty_id,
      :la_type,
      :tenant_id
      # NOTE: :balance intentionally excluded — never writable via API
      # NOTE: :ancestor_ids intentionally excluded — populated by the
      #       ledger_accounts_resolve_ancestor_ids DB trigger.
    ])
    |> validate_required([
      :account_holder_id,
      :ledger_id,
      :currency,
      :regime,
      :la_type,
      :tenant_id
    ])
    |> validate_length(:currency, is: 3)
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:ledger_id)
    |> foreign_key_constraint(:payment_account_id)
    |> foreign_key_constraint(:counterparty_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:ledger_id, :regime],
      name: :ledger_accounts_ledger_regime_root_unique
    )
    |> unique_constraint([:ledger_id, :payment_account_id, :regime],
      name: :ledger_accounts_ledger_pa_regime_unique
    )
    |> unique_constraint([:ledger_id, :counterparty_id, :regime],
      name: :ledger_accounts_ledger_cp_regime_unique
    )
    |> unique_constraint(:ledger_account_number,
      name: :ledger_accounts_ledger_account_number_unique
    )
    |> check_constraint(:la_type,
      name: :ledger_accounts_la_type_shape_check,
      message: "does not match (payment_account_id, counterparty_id, regime)"
    )
    |> check_constraint(:ancestor_ids,
      name: :ledger_accounts_ancestor_resolution,
      message:
        "missing ancestor LedgerAccount — create the *_root row(s) before inserting this descendant"
    )
  end
end
