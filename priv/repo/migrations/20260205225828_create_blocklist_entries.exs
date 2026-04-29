defmodule AtomicFi.Repo.Migrations.CreateBlocklistEntries do
  use Ecto.Migration

  def change do
    create table(:blocklist_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :scope, :string, null: false
      add :entry_type, :string, null: false
      add :term, :text, null: false
      add :reason, :text
      add :active, :boolean, default: true, null: false
      add :added_by_id, references(:users, on_delete: :nilify_all, type: :binary_id)
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Multi-tenancy indexes
    create index(:blocklist_entries, [:tenant_id])
    create index(:blocklist_entries, [:added_by_id])
    create index(:blocklist_entries, [:active])
    create index(:blocklist_entries, [:scope])

    # Composite unique index to prevent duplicate entries per tenant/scope/term
    # Uniqueness applies regardless of active status to prevent duplicates
    create unique_index(:blocklist_entries, [:tenant_id, :scope, :term],
             name: :blocklist_entries_unique_per_tenant
           )
  end
end
