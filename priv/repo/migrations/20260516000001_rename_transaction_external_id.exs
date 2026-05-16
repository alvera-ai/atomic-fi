defmodule AtomicFi.Repo.Migrations.RenameTransactionExternalId do
  use Ecto.Migration

  def up do
    drop_if_exists index(:transactions, [:transaction_external_id, :tenant_id],
                     name: :transactions_external_id_tenant_unique
                   )

    rename table(:transactions), :transaction_external_id, to: :external_id

    create unique_index(:transactions, [:external_id, :tenant_id],
             where: "external_id IS NOT NULL",
             name: :transactions_external_id_tenant_unique
           )
  end

  def down do
    drop_if_exists index(:transactions, [:external_id, :tenant_id],
                     name: :transactions_external_id_tenant_unique
                   )

    rename table(:transactions), :external_id, to: :transaction_external_id

    create unique_index(:transactions, [:transaction_external_id, :tenant_id],
             where: "transaction_external_id IS NOT NULL",
             name: :transactions_external_id_tenant_unique
           )
  end
end
