defmodule AtomicFi.Repo.Migrations.AddAccountHolderIndexes do
  use Ecto.Migration

  def change do
    # Align with platform CDC target: unique index on account_holder_number
    # Platform: unique_index(:account_holders, [:account_holder_number], name: :account_holders_number_unique)
    create unique_index(:account_holders, [:account_holder_number],
             where: "account_holder_number IS NOT NULL",
             name: :account_holders_number_unique
           )

    # Align with platform CDC target: index on risk_level
    create index(:account_holders, [:risk_level])
  end
end
