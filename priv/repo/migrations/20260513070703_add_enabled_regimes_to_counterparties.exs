defmodule AtomicFi.Repo.Migrations.AddEnabledRegimesToCounterparties do
  use Ecto.Migration

  def change do
    alter table(:counterparties) do
      add :enabled_regimes, {:array, :string}, null: false, default: []
    end
  end
end
