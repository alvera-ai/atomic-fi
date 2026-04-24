defmodule PaymentCompliancePlatform.Repo.Migrations.CreateAccountActivitySnapshots do
  use Ecto.Migration

  def change do
    create table(:account_activity_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Subject anchor — always present
      add :account_holder_id,
          references(:account_holders, type: :binary_id, on_delete: :restrict),
          null: false

      # Optional link to a specific PaymentAccount for account-level reporting
      # camt:052/053 <Acct> — if nil, snapshot covers all accounts for the holder
      add :payment_account_id,
          references(:payment_accounts, type: :binary_id, on_delete: :restrict),
          null: true

      # Optional link to a LedgerAccount for chart-of-accounts reporting
      # camt:053 <Ntry><NtryDtls><TxDtls><RltdPties><DbtrAcct>
      add :ledger_account_id,
          references(:ledger_accounts, type: :binary_id, on_delete: :restrict),
          null: true

      # Snapshot type — what period this covers
      # :intraday → camt:052 (live account report, partial day)
      # :daily    → camt:053 (end-of-day statement)
      # :weekly   → weekly summary
      # :monthly  → monthly statement (FinCEN AML lookback)
      add :snapshot_type, :string, null: false

      # Reporting period: from/to timestamps (inclusive)
      add :period_start, :utc_datetime_usec, null: false
      add :period_end, :utc_datetime_usec, null: false

      # Opening/closing balance (camt:053 <Bal> BkToCstmrAcctRpt)
      # In minor currency units (cents). Null if not yet computed.
      add :opening_balance, :integer, null: true
      add :closing_balance, :integer, null: true

      # ISO 4217 currency for the balance amounts
      add :currency, :string, null: true

      # Aggregate debit/credit counts and amounts for the period
      # camt:052/053 <TtlNtries> — total entries by direction
      add :total_debit_count, :integer, null: false, default: 0
      add :total_credit_count, :integer, null: false, default: 0
      add :total_debit_amount, :integer, null: false, default: 0
      add :total_credit_amount, :integer, null: false, default: 0

      # Transaction count (total, independent of direction)
      add :transaction_count, :integer, null: false, default: 0

      # Snapshot status:
      # :pending   — queued, not yet computed
      # :computed  — aggregates are final for the period
      # :published — sent to downstream / regulatory reporting
      add :status, :string, null: false, default: "pending"

      # AML flags — FinCEN AML lookback / suspicious activity detection
      # flagged = true when activity patterns trigger AML review
      add :flagged_for_review, :boolean, null: false, default: false
      add :review_reason, :string, null: true

      # External reference for SAR (Suspicious Activity Report) filing
      add :sar_reference, :string, null: true

      # Caller-supplied idempotency key (unique per tenant when set)
      add :external_reference, :string, null: true

      # Multi-tenancy
      add :tenant_id,
          references(:tenants, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Primary access patterns
    create index(:account_activity_snapshots, [:account_holder_id])
    create index(:account_activity_snapshots, [:payment_account_id])
    create index(:account_activity_snapshots, [:ledger_account_id])
    create index(:account_activity_snapshots, [:tenant_id])
    create index(:account_activity_snapshots, [:status])
    create index(:account_activity_snapshots, [:snapshot_type])
    create index(:account_activity_snapshots, [:period_start, :period_end])
    create index(:account_activity_snapshots, [:flagged_for_review])

    # Compound indexes for common queries
    create index(:account_activity_snapshots, [:account_holder_id, :snapshot_type, :period_start])

    create index(:account_activity_snapshots, [
             :tenant_id,
             :snapshot_type,
             :period_start
           ])

    # Sparse unique: external_reference is unique per tenant when set
    create unique_index(:account_activity_snapshots, [:external_reference, :tenant_id],
             where: "external_reference IS NOT NULL",
             name: :account_activity_snapshots_external_ref_tenant_unique
           )
  end
end
