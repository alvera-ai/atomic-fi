defmodule AtomicFi.Repo.Migrations.AddRejectionMetadataToLedgerEntries do
  use Ecto.Migration

  def change do
    alter table(:ledger_entries) do
      # When create_entries inserts an entry :voided because a rule engine control
      # limit was hit, these record which ledger account / period / direction / rule.
      # All NULL when the entry posted normally.
      add :rejected_ledger_account_id,
          references(:ledger_accounts, type: :binary_id, on_delete: :nilify_all)

      add :rejected_period, :string
      add :rejected_direction, :string
      add :rejected_rule, :string
      add :rejected_code, :string
    end

    create index(:ledger_entries, [:rejected_ledger_account_id])
  end
end
