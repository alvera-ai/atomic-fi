defmodule AtomicFi.Repo.Migrations.AddWalletColumnsToPaymentAccounts do
  use Ecto.Migration

  def change do
    alter table(:payment_accounts) do
      add :wallet_address, :string
      add :wallet_chain, :string
    end
  end
end
