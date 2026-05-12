defmodule AtomicFi.Repo.Migrations.AddRejectionMetadataToTransactions do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      # Rejection metadata, denormalised from the offending ledger entry — populated
      # when the transaction is :rejected because a rule engine velocity limit was hit.
      # All NULL otherwise.
      add :rejected_ledger_account_id,
          references(:ledger_accounts, type: :binary_id, on_delete: :nilify_all)

      # "daily" | "weekly" | "monthly" | "yearly"
      add :rejected_period, :string
      # "debit" | "credit"
      add :rejected_direction, :string
      # the rule that set the breached cap
      add :rejected_rule, :string
      # e.g. "LIMIT_EXCEEDED"
      add :rejected_code, :string
    end

    create index(:transactions, [:rejected_ledger_account_id])
  end
end
