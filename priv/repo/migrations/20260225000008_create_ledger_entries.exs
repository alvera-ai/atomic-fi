defmodule AtomicFi.Repo.Migrations.CreateLedgerEntries do
  use Ecto.Migration

  def change do
    create table(:ledger_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # FK to account_holders — MDM subject
      add :account_holder_id,
          references(:account_holders, type: :binary_id, on_delete: :restrict),
          null: false

      # FK to ledger_accounts — parent account
      add :ledger_account_id,
          references(:ledger_accounts, type: :binary_id, on_delete: :restrict),
          null: false

      # ISO 4217 three-letter currency code — inherited from parent LedgerAccount → Ledger
      add :currency, :string, null: false, size: 3

      # Amount in minor currency units (e.g. cents for USD) — must be >= 0
      add :amount, :integer, null: false

      # ISO 20022 CdtDbtInd — credit or debit
      add :entry_type, :string, null: false

      # LedgerEntry lifecycle status — includes :voided for trigger-driven balance reversal
      add :status, :string, null: false, default: "pending"

      # ISO 20022 ValDt — value/settlement date (nullable)
      add :entry_date, :date

      # Opaque external SoE identifier (nullable — upsert identity)
      add :external_entry_id, :string

      # ── Control limit snapshots (set by orchestration layer from risk engine) ─────
      # These are audit records of what limits were in effect at time of entry creation.
      # The trigger reads these columns and copies them to ledger_account_balances.last_*_limit
      # so CHECK constraints on the balance table reflect the most recent risk engine decision.
      # NULL = unconstrained for that direction/period (risk engine sent no limit).
      add :daily_debit_limit_at_entry, :integer
      add :daily_credit_limit_at_entry, :integer
      add :weekly_debit_limit_at_entry, :integer
      add :weekly_credit_limit_at_entry, :integer
      add :monthly_debit_limit_at_entry, :integer
      add :monthly_credit_limit_at_entry, :integer
      add :yearly_debit_limit_at_entry, :integer
      add :yearly_credit_limit_at_entry, :integer

      # RLS scope
      add :tenant_id,
          references(:tenants, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:ledger_entries, [:tenant_id])
    create index(:ledger_entries, [:account_holder_id])
    create index(:ledger_entries, [:ledger_account_id])
    create index(:ledger_entries, [:entry_date])
    create index(:ledger_entries, [:status])

    # Upsert key: external_entry_id when present
    create unique_index(:ledger_entries, [:external_entry_id],
             where: "external_entry_id IS NOT NULL",
             name: :ledger_entries_external_entry_id_unique
           )
  end
end
