defmodule AtomicFi.TransactionContext.Transaction do
  use AtomicFi.Schema

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.ComplianceScreeningContext.ComplianceScreening
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.LedgerAccountContext.LedgerAccount
  alias AtomicFi.LedgerEntryContext.LedgerEntry
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  alias AtomicFi.TenantContext.Tenant

  @typedoc """
  Transaction — one row per payment instruction or transfer event.

  ## ISO 20022 Alignment

  Covers the full payment lifecycle across ISO 20022 message families:

  - `pain:001` — CustomerCreditTransferInitiation (originates the transaction)
  - `pacs:008` — FIToFICustomerCreditTransfer (interbank settlement)
  - `pacs:002` — FIToFIPaymentStatusReport (status updates / rejections)
  - `pacs:004` — PaymentReturn (reversals / refunds)
  - `camt:054` — BankToCustomerDebitCreditNotification (booking confirmation)

  ## FATF Recommendation 16 — Wire Transfer Rule

  Every transaction must reference a `debtor_payment_account_id` (payer) and
  optionally a `creditor_payment_account_id` (payee) — both must be verified
  PaymentAccounts linked to verified AccountHolders. This satisfies the FATF R16
  originator/beneficiary information requirement for wire transfers.

  ## PCI-DSS 4.0

  Raw PAN data must never appear in transaction fields. Use tokenised card references
  via the linked PaymentAccount only.

  ## Attributes

  * `id` - UUID primary key
  * `account_holder_id` - FK to AccountHolder (MDM subject, required)
  * `debtor_payment_account_id` - FK to PaymentAccount (payer — pain:001 <DbtrAcct>)
  * `creditor_payment_account_id` - FK to PaymentAccount (payee — pain:001 <CdtrAcct>)
  * `debtor_counterparty_id` - FK to Counterparty (payer — pain:001 <Dbtr>)
  * `creditor_counterparty_id` - FK to Counterparty (payee — pain:001 <Cdtr>)
  * `ledger_entry_id` - FK to LedgerEntry (camt:052/053 Ntry — accounting record)
  * `compliance_screening_id` - FK to ComplianceScreening (AML/sanctions check)
  * `transaction_type` - ISO 20022 payment type (`:credit_transfer` | `:direct_debit` | `:card_payment` | `:refund` | `:reversal` | `:internal_transfer`)
  * `status` - Payment lifecycle status (`:pending` | `:accepted` | `:settled` | `:rejected` | `:reversed` | `:cancelled`)
  * `amount` - Amount in minor currency units (cents, always positive)
  * `currency` - ISO 4217 3-letter currency code
  * `end_to_end_id` - pain:001 EndToEndId (set by originator, immutable)
  * `uetr` - SWIFT gpi UETR (Unique End-to-End Transaction Reference — ISO 20022)
  * `instruction_id` - pain:001 TxId (instruction ID from the payment initiation)
  * `status_reason_code` - pacs:002 status reason code (e.g. "RJCT", "ACCP", "ACSC")
  * `requested_execution_date` - pain:001 ReqdExctnDt
  * `settlement_date` - Actual settlement date (pacs:008 IntrBkSttlmDt / camt:054 BookgDt)
  * `external_id` - Caller-supplied SoE upsert key (unique per tenant when set)
  * `rejected_ledger_account_id` - FK to the LedgerAccount whose control limit was breached (NULL unless `:rejected` for a limit)
  * `rejected_period` - `"daily" | "weekly" | "monthly" | "yearly"` (NULL unless rejected)
  * `rejected_direction` - `"debit" | "credit"` (NULL unless rejected)
  * `rejected_rule` - the rule that set the breached cap (NULL unless rejected)
  * `rejected_code` - e.g. `"LIMIT_EXCEEDED"` (NULL unless rejected)
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
      :debtor_payment_account_id,
      :creditor_payment_account_id,
      :debtor_counterparty_id,
      :creditor_counterparty_id,
      :ledger_entry_id,
      :compliance_screening_id,
      :transaction_type,
      :status,
      :currency,
      :settlement_date
    ],
    sortable: [
      :id,
      :inserted_at,
      :updated_at,
      :status,
      :transaction_type,
      :amount,
      :currency,
      :settlement_date,
      :requested_execution_date
    ],
    default_limit: 20,
    max_limit: 100
  }

  # ── OpenAPI annotations ──────────────────────────────────────────────────────

  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{
      type: :string,
      enum: [
        "credit_transfer",
        "direct_debit",
        "card_payment",
        "refund",
        "reversal",
        "internal_transfer"
      ],
      description: "ISO 20022 payment instruction type"
    },
    key: :transaction_type
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: ["pending", "accepted", "settled", "rejected", "reversed", "cancelled"],
      description: "Payment lifecycle status (pain:002 / pacs:002 TxSts)"
    },
    key: :status
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      description: "Amount in minor currency units (cents) — always positive"
    },
    key: :amount
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      description: "ISO 4217 3-letter currency code (e.g. USD, EUR, GBP)"
    },
    key: :currency
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "pain:001 EndToEndId — set by originating party, immutable once set"
    },
    key: :end_to_end_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description:
        "SWIFT gpi UETR (Unique End-to-End Transaction Reference — ISO 20022). Globally unique."
    },
    key: :uetr
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "pain:001 TxId — instruction ID from the payment initiation message"
    },
    key: :instruction_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "pacs:002 TxSts reason code (e.g. RJCT, ACCP, ACSC, PDNG)"
    },
    key: :status_reason_code
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :date,
      nullable: true,
      description: "Requested execution date (pain:001 ReqdExctnDt)"
    },
    key: :requested_execution_date
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :date,
      nullable: true,
      description: "Actual settlement date (pacs:008 IntrBkSttlmDt / camt:054 BookgDt)"
    },
    key: :settlement_date
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "Caller-supplied SoE upsert key (unique per tenant when set)"
    },
    key: :external_id
  )

  # Rejection metadata, denormalised from the offending ledger entry — populated when
  # the transaction is :rejected because a rule engine control limit was hit. NULL otherwise.
  open_api_property(
    schema: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      readOnly: true,
      description: "LedgerAccount whose control limit was breached (NULL unless rejected)."
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

  open_api_property(schema: %Schema{type: :string, format: :uuid}, key: :account_holder_id)

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      description: "Debtor (payer) payment account — pain:001 <DbtrAcct>"
    },
    key: :debtor_payment_account_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      description: "Creditor (payee) payment account — pain:001 <CdtrAcct>"
    },
    key: :creditor_payment_account_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      description: "Debtor (payer) counterparty — pain:001 <Dbtr>"
    },
    key: :debtor_counterparty_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      description: "Creditor (payee) counterparty — pain:001 <Cdtr>"
    },
    key: :creditor_counterparty_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      description: "LedgerEntry created by this transaction (camt:052/053 Ntry)"
    },
    key: :ledger_entry_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      description: "ComplianceScreening result for this transaction (auth:018 / camt:998)"
    },
    key: :compliance_screening_id
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
    title: "Transaction",
    description:
      "Payment transaction — one row per payment instruction or transfer event. " <>
        "Covers pain:001 (initiation), pacs:008 (interbank), pacs:002 (status), " <>
        "pacs:004 (return), camt:054 (booking notification). " <>
        "FATF Rec 16: debtor/creditor payment accounts must be verified before settlement.",
    required: [:transaction_type, :amount, :currency, :account_holder_id, :tenant_id],
    properties: [
      :id,
      :transaction_type,
      :status,
      :amount,
      :currency,
      :end_to_end_id,
      :uetr,
      :instruction_id,
      :status_reason_code,
      :requested_execution_date,
      :settlement_date,
      :external_id,
      :rejected_ledger_account_id,
      :rejected_period,
      :rejected_direction,
      :rejected_rule,
      :rejected_code,
      :account_holder_id,
      :debtor_payment_account_id,
      :creditor_payment_account_id,
      :debtor_counterparty_id,
      :creditor_counterparty_id,
      :ledger_entry_id,
      :compliance_screening_id,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "transactions" do
    field :transaction_type, Ecto.Enum,
      values: [
        :credit_transfer,
        :direct_debit,
        :card_payment,
        :refund,
        :reversal,
        :internal_transfer
      ]

    field :status, Ecto.Enum,
      values: [:pending, :accepted, :settled, :rejected, :reversed, :cancelled],
      default: :pending

    field :amount, :integer
    field :currency, :string

    # ISO 20022 references
    field :end_to_end_id, :string
    field :uetr, :string
    field :instruction_id, :string
    field :status_reason_code, :string

    # Settlement dates
    field :requested_execution_date, :date
    field :settlement_date, :date

    # Identifiers
    field :external_id, :string

    # Rejection metadata, denormalised from the offending ledger entry. Set by the
    # orchestration layer when the transaction is :rejected for a control limit.
    belongs_to :rejected_ledger_account, LedgerAccount, foreign_key: :rejected_ledger_account_id
    field :rejected_period, :string
    field :rejected_direction, :string
    field :rejected_rule, :string
    field :rejected_code, :string

    # Relationships — subject anchor
    belongs_to :account_holder, AccountHolder

    # Relationships — payment accounts (pain:001 DbtrAcct / CdtrAcct)
    belongs_to :debtor_payment_account, PaymentAccount, foreign_key: :debtor_payment_account_id

    belongs_to :creditor_payment_account, PaymentAccount,
      foreign_key: :creditor_payment_account_id

    # Relationships — counterparties (pain:001 Dbtr / Cdtr)
    belongs_to :debtor_counterparty, Counterparty, foreign_key: :debtor_counterparty_id

    belongs_to :creditor_counterparty, Counterparty, foreign_key: :creditor_counterparty_id

    # Relationships — accounting + compliance
    belongs_to :ledger_entry, LedgerEntry
    belongs_to :compliance_screening, ComplianceScreening

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :transaction_type,
      :amount,
      :currency,
      :end_to_end_id,
      :uetr,
      :instruction_id,
      :status_reason_code,
      :requested_execution_date,
      :settlement_date,
      :external_id,
      :rejected_ledger_account_id,
      :rejected_period,
      :rejected_direction,
      :rejected_rule,
      :rejected_code,
      :account_holder_id,
      :debtor_payment_account_id,
      :creditor_payment_account_id,
      :debtor_counterparty_id,
      :creditor_counterparty_id,
      :ledger_entry_id,
      :compliance_screening_id,
      :tenant_id
    ])
    |> maybe_cast_status(attrs)
    |> validate_required([:transaction_type, :amount, :currency, :account_holder_id, :tenant_id])
    |> validate_number(:amount, greater_than: 0)
    |> foreign_key_constraint(:rejected_ledger_account_id)
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:debtor_payment_account_id)
    |> foreign_key_constraint(:creditor_payment_account_id)
    |> foreign_key_constraint(:debtor_counterparty_id)
    |> foreign_key_constraint(:creditor_counterparty_id)
    |> foreign_key_constraint(:ledger_entry_id)
    |> foreign_key_constraint(:compliance_screening_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:external_id, :tenant_id],
      name: :transactions_external_id_tenant_unique,
      message: "has already been taken"
    )
    |> unique_constraint([:end_to_end_id, :tenant_id],
      name: :transactions_end_to_end_id_tenant_unique,
      message: "has already been taken"
    )
    |> unique_constraint([:uetr],
      name: :transactions_uetr_unique,
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
end
