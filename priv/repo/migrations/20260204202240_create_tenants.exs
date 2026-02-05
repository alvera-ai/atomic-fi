defmodule PaymentCompliancePlatform.Repo.Migrations.CreateTenants do
  use Ecto.Migration

  def change do
    create table(:tenants,
             primary_key: false,
             comment: "Top-level multi-tenancy entity. Each tenant is a separate data partition."
           ) do
      add :id, :binary_id, primary_key: true

      add :name, :string,
        null: false,
        comment: "Tenant name (organization/company name)"

      add :slug, :string, comment: "URL-safe identifier for tenant (e.g., acme-corp)"

      add :status, :string,
        default: "active",
        comment: "Lifecycle status: active, suspended, inactive"

      add :metadata, :map,
        default: %{},
        comment: "Tenant-specific configuration and settings"

      timestamps(type: :utc_datetime_usec)
    end

    # Multi-tenancy: tenant_id generated from id for RLS
    # Allows Tenant to participate in RLS queries without self-reference
    execute(
      "ALTER TABLE tenants ADD COLUMN tenant_id UUID GENERATED ALWAYS AS (id) STORED",
      "ALTER TABLE tenants DROP COLUMN tenant_id"
    )

    create unique_index(:tenants, [:slug])
    # Multi-tenancy indexes
    create index(:tenants, [:tenant_id])
  end
end
