defmodule AtomicFi.Repo.Migrations.CreateCustomers do
  use Ecto.Migration

  def change do
    create table(:customers,
             primary_key: false,
             comment: "Customer organizations within a tenant"
           ) do
      add :id, :binary_id, primary_key: true

      add :name, :string,
        null: false,
        comment: "Customer organization name"

      add :slug, :string, comment: "URL-friendly identifier"

      add :description, :text, comment: "Customer description"

      add :status, :string,
        default: "active",
        null: false,
        comment: "Status: active, inactive, suspended"

      add :metadata, :map,
        default: %{},
        null: false,
        comment: "Additional customer configuration"

      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all),
        null: false,
        comment: "FK to tenant for multi-tenancy isolation (RLS)"

      timestamps(type: :utc_datetime_usec)
    end

    # Virtual customer_id field using GENERATED ALWAYS AS
    execute(
      "ALTER TABLE customers ADD COLUMN customer_id UUID GENERATED ALWAYS AS (id) STORED",
      "ALTER TABLE customers DROP COLUMN customer_id"
    )

    create index(:customers, [:tenant_id])
    create index(:customers, [:status])
    create unique_index(:customers, [:slug, :tenant_id], where: "slug IS NOT NULL")
  end
end
