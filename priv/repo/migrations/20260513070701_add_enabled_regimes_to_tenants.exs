defmodule AtomicFi.Repo.Migrations.AddEnabledRegimesToTenants do
  use Ecto.Migration

  def change do
    alter table(:tenants) do
      add :enabled_regimes, {:array, :string}, null: false, default: []
    end
  end
end
