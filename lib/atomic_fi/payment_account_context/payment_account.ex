defmodule AtomicFi.PaymentAccountContext.PaymentAccount do
  use AtomicFi.Schema

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.LedgerAccountContext.LedgerAccount
  alias AtomicFi.LegalEntityContext.LegalEntity
  alias AtomicFi.TenantContext.Tenant

  @typedoc """
  Payment account — one row per payment instrument linked to an AccountHolder.

  ## ISO 20022 Alignment

  Maps to `pain:001 <DbtrAcct>/<CdtrAcct>` — the specific account involved in
  a payment instruction. Enables FATF Recommendation 16 (wire transfer rule)
  compliance by anchoring every payment to a known, verified account.

  Accounts may be:
  - Bank accounts (sort code + account number, IBAN)
  - Cards (tokenised PAN)
  - E-wallets / digital wallets
  - Crypto wallets (blockchain address)

  ## Subject Anchor

  `account_holder_id` is always the MDM subject (compliance entity). One
  AccountHolder may have many payment accounts of different types and currencies.

  ## PCI-DSS 4.0 Note

  `account_number`, `routing_number`, `iban`, `card_pan` are PCI-DSS sensitive
  fields. The calling orchestration layer is responsible for tokenisation before
  writing to this SoE. `card_pan` must contain only last-4 digits or a token —
  never a raw PAN.

  ## Attributes

  * `id` - UUID primary key
  * `account_holder_id` - FK to AccountHolder (MDM subject, required)
  * `legal_entity_id` - FK to LegalEntity (optional PII anchor)
  * `counterparty_id` - FK to Counterparty (optional, for external payer/payee)
  * `ledger_account_id` - FK to LedgerAccount (optional, maps to chart-of-accounts)
  * `account_type` - Type of payment instrument (`:bank_account` | `:card` | `:wallet` | `:crypto_wallet`)
  * `status` - Lifecycle state (`:active` | `:suspended` | `:blocked`)
  * `currency` - ISO 4217 3-letter currency code (e.g. `"USD"`, `"EUR"`)
  * `account_number` - Bank account number (PCI-DSS sensitive — tokenise before storing)
  * `routing_number` - Bank routing / sort code
  * `iban` - International Bank Account Number
  * `swift_bic` - SWIFT/BIC code of the account's bank
  * `bank_name` - Name of the account's bank
  * `card_pan` - Card PAN last-4 or token (PCI-DSS — never raw PAN)
  * `payment_account_number` - Opaque internal account number
  * `payment_account_external_id` - Caller-supplied SoE upsert key (unique per tenant)
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
      :legal_entity_id,
      :counterparty_id,
      :ledger_account_id,
      :account_type,
      :status,
      :currency
    ],
    sortable: [:id, :inserted_at, :updated_at, :account_type, :status, :currency],
    default_limit: 20,
    max_limit: 100
  }

  # ── OpenAPI annotations ──────────────────────────────────────────────────────

  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{
      type: :string,
      enum: ["bank_account", "card", "wallet", "crypto_wallet"]
    },
    key: :account_type
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: ["active", "suspended", "blocked"]
    },
    key: :status
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
      type: :string,
      nullable: true,
      description: "Bank account number (PCI-DSS sensitive — tokenise before storing)"
    },
    key: :account_number
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "Bank routing / sort code"
    },
    key: :routing_number
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "International Bank Account Number (IBAN)"
    },
    key: :iban
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "SWIFT/BIC code of the account's bank"
    },
    key: :swift_bic
  )

  open_api_property(
    schema: %Schema{type: :string, nullable: true, description: "Name of the account's bank"},
    key: :bank_name
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "Card PAN last-4 or token (PCI-DSS — never store raw PAN)"
    },
    key: :card_pan
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description:
        "On-chain wallet address (the actual identifier funds settle to). " <>
          "Set together with wallet_chain when account_type = :crypto_wallet."
    },
    key: :wallet_address
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description:
        ~s|Blockchain / asset ticker the wallet_address lives on (e.g. "BTC", "ETH", "TRON"). Disambiguates same-format addresses across chains.|
    },
    key: :wallet_chain
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "Opaque internal payment account number"
    },
    key: :payment_account_number
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "Caller-supplied SoE upsert key (unique per tenant when set)"
    },
    key: :payment_account_external_id
  )

  open_api_property(schema: %Schema{type: :string, format: :uuid}, key: :account_holder_id)

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, nullable: true},
    key: :legal_entity_id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, nullable: true},
    key: :counterparty_id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, nullable: true},
    key: :ledger_account_id
  )

  open_api_property(
    schema: %Schema{type: :array, nullable: true, items: %Schema{type: :string}},
    key: :enabled_regimes
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
    title: "PaymentAccount",
    description:
      "Payment account — one row per payment instrument linked to an AccountHolder " <>
        "(ISO 20022 pain:001 <DbtrAcct>/<CdtrAcct>). " <>
        "Gates FATF Recommendation 16 wire transfer rule compliance. " <>
        "PCI-DSS 4.0: account_number, iban, card_pan must be tokenised before writing.",
    required: [:account_type, :account_holder_id, :tenant_id],
    properties: [
      :id,
      :account_type,
      :status,
      :currency,
      :account_number,
      :routing_number,
      :iban,
      :swift_bic,
      :bank_name,
      :card_pan,
      :wallet_address,
      :wallet_chain,
      :payment_account_number,
      :payment_account_external_id,
      :account_holder_id,
      :legal_entity_id,
      :counterparty_id,
      :ledger_account_id,
      :enabled_regimes,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "payment_accounts" do
    field :account_type, Ecto.Enum, values: [:bank_account, :card, :wallet, :crypto_wallet]

    field :status, Ecto.Enum,
      values: [:active, :suspended, :blocked],
      default: :active

    field :currency, :string

    # Bank / card details (PCI-DSS 4.0 sensitive)
    field :account_number, :string
    field :routing_number, :string
    field :iban, :string
    field :swift_bic, :string
    field :bank_name, :string
    field :card_pan, :string

    # Crypto-wallet rail (account_type :crypto_wallet). wallet_chain
    # disambiguates same-format addresses across chains (e.g. USDT on
    # ETH vs TRON). Both must be set together for the on-chain screen.
    field :wallet_address, :string
    field :wallet_chain, :string

    # Identifiers
    field :payment_account_number, :string
    field :payment_account_external_id, :string

    # Hierarchical enabled regimes — populated by parent (AH or CP) at create
    # via AtomicFi.EnabledRegimes; subset of parent.enabled_regimes.
    field :enabled_regimes, {:array, :string}, default: []

    # Relationships
    belongs_to :account_holder, AccountHolder
    belongs_to :legal_entity, LegalEntity
    belongs_to :counterparty, Counterparty
    belongs_to :ledger_account, LedgerAccount

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    # FK to the currently-scheduled OnboardingWorker job. Owned by
    # OnboardingContext / OnboardingWorker — see their moduledocs.
    belongs_to :rescreen_job, Oban.Job, type: :integer

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(payment_account, attrs) do
    payment_account
    |> cast(attrs, [
      :account_type,
      :currency,
      :account_number,
      :routing_number,
      :iban,
      :swift_bic,
      :bank_name,
      :card_pan,
      :wallet_address,
      :wallet_chain,
      :payment_account_number,
      :payment_account_external_id,
      :account_holder_id,
      :legal_entity_id,
      :counterparty_id,
      :ledger_account_id,
      :enabled_regimes,
      :tenant_id
    ])
    |> maybe_cast_status(attrs)
    |> validate_required([:account_type, :account_holder_id, :currency, :tenant_id])
    |> validate_length(:currency, is: 3)
    |> cast_and_validate_enabled_regimes()
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:legal_entity_id)
    |> foreign_key_constraint(:counterparty_id)
    |> foreign_key_constraint(:ledger_account_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:payment_account_external_id, :tenant_id],
      name: :payment_accounts_external_id_tenant_unique,
      message: "has already been taken"
    )
    |> unique_constraint([:payment_account_number, :tenant_id],
      name: :payment_accounts_number_tenant_unique,
      message: "has already been taken"
    )
  end

  # Parent is the linked Counterparty (when counterparty_id is set) or the
  # linked AccountHolder otherwise. Repo lookup deferred via prepare_changes/2.
  defp cast_and_validate_enabled_regimes(changeset) do
    Ecto.Changeset.prepare_changes(changeset, fn prepared ->
      {parent_module, parent_id} =
        case Ecto.Changeset.get_field(prepared, :counterparty_id) do
          nil -> {AccountHolder, Ecto.Changeset.get_field(prepared, :account_holder_id)}
          counterparty_id -> {Counterparty, counterparty_id}
        end

      parent_regimes =
        case parent_id &&
               prepared.repo.get(parent_module, parent_id, skip_multi_tenancy_check: true) do
          %{enabled_regimes: regimes} -> regimes
          _ -> AtomicFi.EnabledRegimes.default()
        end

      AtomicFi.EnabledRegimes.cast_and_validate(
        prepared,
        Ecto.Changeset.get_field(prepared, :enabled_regimes),
        parent_regimes
      )
    end)
  end

  # Only cast status when explicitly provided and non-nil.
  # ExOpenApiUtils.Changeset.cast/3 calls Mapper.to_map internally, which includes all struct
  # fields even when nil. Casting nil status would override the Ecto/DB default of :active.
  defp maybe_cast_status(changeset, attrs) do
    status = Map.get(attrs, :status)

    if is_nil(status) do
      changeset
    else
      Ecto.Changeset.cast(changeset, %{status: status}, [:status])
    end
  end
end
