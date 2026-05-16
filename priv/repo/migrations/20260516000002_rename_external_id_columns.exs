defmodule AtomicFi.Repo.Migrations.RenameExternalIdColumns do
  use Ecto.Migration

  def up do
    # payment_accounts.payment_account_external_id → external_id
    drop_if_exists index(:payment_accounts, [:payment_account_external_id, :tenant_id],
                     name: :payment_accounts_external_id_tenant_unique
                   )

    rename table(:payment_accounts), :payment_account_external_id, to: :external_id

    create unique_index(:payment_accounts, [:external_id, :tenant_id],
             where: "external_id IS NOT NULL",
             name: :payment_accounts_external_id_tenant_unique
           )

    # counterparties.counterparty_number → external_id
    drop_if_exists index(:counterparties, [:counterparty_number],
                     name: :counterparties_number_unique
                   )

    rename table(:counterparties), :counterparty_number, to: :external_id

    create unique_index(:counterparties, [:external_id],
             where: "external_id IS NOT NULL",
             name: :counterparties_external_id_unique
           )
  end

  def down do
    drop_if_exists index(:payment_accounts, [:external_id, :tenant_id],
                     name: :payment_accounts_external_id_tenant_unique
                   )

    rename table(:payment_accounts), :external_id, to: :payment_account_external_id

    create unique_index(:payment_accounts, [:payment_account_external_id, :tenant_id],
             where: "payment_account_external_id IS NOT NULL",
             name: :payment_accounts_external_id_tenant_unique
           )

    drop_if_exists index(:counterparties, [:external_id],
                     name: :counterparties_external_id_unique
                   )

    rename table(:counterparties), :external_id, to: :counterparty_number

    create unique_index(:counterparties, [:counterparty_number],
             where: "counterparty_number IS NOT NULL",
             name: :counterparties_number_unique
           )
  end
end
