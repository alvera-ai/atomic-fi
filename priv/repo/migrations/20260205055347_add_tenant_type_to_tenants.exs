defmodule AtomicFi.Repo.Migrations.AddTenantTypeToTenants do
  use Ecto.Migration

  def change do
    # Add column with default to handle existing rows
    alter table(:tenants) do
      add :tenant_type, :string,
        default: "standard",
        null: false,
        comment: "Tenant type: platform (root tenant) or standard (user tenant)"
    end

    # Remove default after backfill (keeps NOT NULL constraint)
    alter table(:tenants) do
      modify :tenant_type, :string, null: false
    end

    create index(:tenants, [:tenant_type])
  end
end
