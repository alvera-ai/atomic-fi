defmodule PaymentCompliancePlatform.Repo.Migrations.CreateTransactions do
  use Ecto.Migration

  def change do
    create table(:transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # ── Subject anchor (MDM subject — required) ──────────────────────────────
      add :account_holder_id,
          references(:account_holders, type: :binary_id, on_delete: :restrict),
          null: false

      # ── ISO 20022 pain:001 / pacs:008 linked accounts ────────────────────────
      # Debtor payment account (payer side — pain:001 <DbtrAcct>)
      add :debtor_payment_account_id,
          references(:payment_accounts, type: :binary_id, on_delete: :restrict),
          null: true

      # Creditor payment account (payee side — pain:001 <CdtrAcct>)
      add :creditor_payment_account_id,
          references(:payment_accounts, type: :binary_id, on_delete: :restrict),
          null: true

      # ── Optional links to related entities ───────────────────────────────────
      # Debtor counterparty (payer — pain:001 <Dbtr>)
      add :debtor_counterparty_id,
          references(:counterparties, type: :binary_id, on_delete: :restrict),
          null: true

      # Creditor counterparty (payee — pain:001 <Cdtr>)
      add :creditor_counterparty_id,
          references(:counterparties, type: :binary_id, on_delete: :restrict),
          null: true

      # LedgerEntry created by this transaction (camt:052/053 Ntry)
      add :ledger_entry_id,
          references(:ledger_entries, type: :binary_id, on_delete: :restrict),
          null: true

      # ComplianceScreening result for this transaction
      add :compliance_screening_id,
          references(:compliance_screenings, type: :binary_id, on_delete: :restrict),
          null: true

      # ── Core transaction fields ───────────────────────────────────────────────
      # ISO 20022 pain:001 transaction type
      add :transaction_type, :string, null: false

      # ISO 20022 payment status (pain:002 StsRsnInf, pacs:002 TxSts)
      add :status, :string, null: false, default: "pending"

      # Amount in minor currency units (cents) — always positive
      add :amount, :integer, null: false

      # ISO 4217 3-letter currency code
      add :currency, :string, null: false

      # ── ISO 20022 references ─────────────────────────────────────────────────
      # pain:001 EndToEndId — set by originating party; immutable once set
      add :end_to_end_id, :string, null: true

      # pacs:008 UETR (Unique End-to-End Transaction Reference — ISO 20022 SWIFT gpi)
      add :uetr, :string, null: true

      # pain:001 TxId — instruction ID from the payment initiation message
      add :instruction_id, :string, null: true

      # pacs:002 TxSts reason code (e.g. "RJCT", "ACCP", "ACSC")
      add :status_reason_code, :string, null: true

      # ── Settlement ────────────────────────────────────────────────────────────
      # Requested execution date (pain:001 ReqdExctnDt)
      add :requested_execution_date, :date, null: true

      # Actual settlement date (pacs:008 IntrBkSttlmDt / camt:054 BookgDt)
      add :settlement_date, :date, null: true

      # ── Identifiers ──────────────────────────────────────────────────────────
      # Caller-supplied SoE upsert key (unique per tenant when set)
      add :transaction_external_id, :string, null: true

      # ── Multi-tenancy (RLS) ───────────────────────────────────────────────────
      add :tenant_id,
          references(:tenants, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    # ── Indexes ──────────────────────────────────────────────────────────────────
    create index(:transactions, [:account_holder_id])
    create index(:transactions, [:debtor_payment_account_id])
    create index(:transactions, [:creditor_payment_account_id])
    create index(:transactions, [:debtor_counterparty_id])
    create index(:transactions, [:creditor_counterparty_id])
    create index(:transactions, [:ledger_entry_id])
    create index(:transactions, [:compliance_screening_id])
    create index(:transactions, [:tenant_id])
    create index(:transactions, [:status])
    create index(:transactions, [:transaction_type])
    create index(:transactions, [:currency])
    create index(:transactions, [:settlement_date])

    # Sparse unique index on transaction_external_id — only enforced when non-null
    create unique_index(:transactions, [:transaction_external_id, :tenant_id],
             where: "transaction_external_id IS NOT NULL",
             name: :transactions_external_id_tenant_unique
           )

    # Sparse unique index on end_to_end_id per tenant — only enforced when non-null
    create unique_index(:transactions, [:end_to_end_id, :tenant_id],
             where: "end_to_end_id IS NOT NULL",
             name: :transactions_end_to_end_id_tenant_unique
           )

    # Sparse unique index on uetr — globally unique per ISO 20022 SWIFT gpi spec
    create unique_index(:transactions, [:uetr],
             where: "uetr IS NOT NULL",
             name: :transactions_uetr_unique
           )
  end
end
