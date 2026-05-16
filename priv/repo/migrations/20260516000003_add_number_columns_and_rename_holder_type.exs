defmodule AtomicFi.Repo.Migrations.AddNumberColumnsAndRenameHolderType do
  use Ecto.Migration

  # Adds atomic-fi-generated `<resource>_number` columns to the schemas that
  # don't have one yet (LE, CP, Txn). AH / BO / PA already have it with a
  # partial unique index in their creation migrations.
  #
  # Also renames AccountHolder.holder_type -> account_holder_type to match
  # LegalEntity.legal_entity_type and improve audit log readability.

  def change do
    alter table(:legal_entities) do
      add :legal_entity_number, :string
    end

    create unique_index(:legal_entities, [:legal_entity_number, :tenant_id],
             where: "legal_entity_number IS NOT NULL",
             name: :legal_entities_number_tenant_unique
           )

    alter table(:counterparties) do
      add :counterparty_number, :string
    end

    create unique_index(:counterparties, [:counterparty_number, :tenant_id],
             where: "counterparty_number IS NOT NULL",
             name: :counterparties_number_tenant_unique
           )

    alter table(:transactions) do
      add :transaction_number, :string
    end

    create unique_index(:transactions, [:transaction_number, :tenant_id],
             where: "transaction_number IS NOT NULL",
             name: :transactions_number_tenant_unique
           )

    rename table(:account_holders), :holder_type, to: :account_holder_type
  end
end
