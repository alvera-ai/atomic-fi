defmodule AtomicFi.Repo.Migrations.AddCountryToPaymentAccounts do
  use Ecto.Migration

  def change do
    alter table(:payment_accounts) do
      add :country, :string, size: 2
    end

    create index(:payment_accounts, [:country])
  end
end
