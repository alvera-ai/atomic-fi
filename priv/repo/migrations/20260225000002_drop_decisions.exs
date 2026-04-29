defmodule AtomicFi.Repo.Migrations.DropDecisions do
  use Ecto.Migration

  def up do
    drop table(:decisions)
  end

  def down do
    create table(:decisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :overall_status, :string, null: false
      add :total_entities_screened, :integer, null: false
      add :entities_with_matches, :integer, null: false
      add :list_synced_at, :utc_datetime_usec, null: false
      add :list_sources, :map
      add :raw_request, :map
      add :entity_decisions, :map

      add :account_holder_id,
          references(:account_holders, type: :binary_id, on_delete: :delete_all),
          null: false

      add :tenant_id,
          references(:tenants, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:decisions, [:account_holder_id])
    create index(:decisions, [:tenant_id])
    create index(:decisions, [:overall_status])
  end
end
