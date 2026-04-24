defmodule PaymentCompliancePlatform.Repo.Migrations.CreateLedgerAccounts do
  use Ecto.Migration

  def change do
    create table(:ledger_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # FK to account_holders — MDM subject
      add :account_holder_id,
          references(:account_holders, type: :binary_id, on_delete: :restrict),
          null: false

      # FK to ledgers — parent chart-of-accounts container
      add :ledger_id,
          references(:ledgers, type: :binary_id, on_delete: :delete_all),
          null: false

      # ISO 4217 three-letter currency code — inherited from parent Ledger
      add :currency, :string, null: false, size: 3

      # Chart-of-accounts account type (ISO 20022 / GAAP classification)
      add :account_type, :string, null: false, default: "asset"

      # LedgerAccount lifecycle status
      add :status, :string, null: false, default: "active"

      # Running balance in minor currency units (e.g. cents for USD)
      # Atomically updated by the ledger_entry_propagate_to_balances trigger
      add :balance, :integer, null: false, default: 0

      # Opaque external SoE identifier (nullable — not PII; used for upsert identity)
      add :ledger_account_number, :string

      # ── Hierarchy ────────────────────────────────────────────────────────────
      # Self-referential parent (nullable — root accounts have no parent)
      add :parent_ledger_account_id,
          references(:ledger_accounts, type: :binary_id, on_delete: :restrict),
          null: true

      # Materialized ancestor path — all ancestor UUIDs flattened for O(1) lookup.
      # Populated by the application at write time. No-cycle check enforced in changeset.
      # Limits are NOT stored here — they are managed by the risk engine and stored on
      # ledger_account_balances rows at entry time.
      add :ancestor_ids, {:array, :binary_id}, null: false, default: []

      # RLS scope
      add :tenant_id,
          references(:tenants, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:ledger_accounts, [:tenant_id])
    create index(:ledger_accounts, [:account_holder_id])
    create index(:ledger_accounts, [:ledger_id])
    create index(:ledger_accounts, [:status])
    create index(:ledger_accounts, [:parent_ledger_account_id])

    # GIN index for fast @> / ANY queries on ancestor_ids array
    execute(
      "CREATE INDEX ledger_accounts_ancestor_ids_gin ON ledger_accounts USING GIN (ancestor_ids)",
      "DROP INDEX IF EXISTS ledger_accounts_ancestor_ids_gin"
    )

    # Natural key: one LedgerAccount per Ledger per account type
    create unique_index(:ledger_accounts, [:ledger_id, :account_type],
             name: :ledger_accounts_ledger_id_account_type_index
           )

    # Upsert key: ledger_account_number when present
    create unique_index(:ledger_accounts, [:ledger_account_number],
             where: "ledger_account_number IS NOT NULL",
             name: :ledger_accounts_ledger_account_number_unique
           )

    # NOTE: No balance CHECK constraint here.
    # Velocity limit enforcement lives on ledger_account_balances via CHECK constraints
    # that reference last_*_limit columns updated by the trigger from entry snapshots.
  end
end
