defmodule AtomicFi.Repo.Migrations.AddEnabledRegimesToAccountHolders do
  use Ecto.Migration

  def change do
    alter table(:account_holders) do
      add :enabled_regimes, {:array, :string}, null: false, default: []
    end
  end
end
