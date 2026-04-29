defmodule AtomicFi.Repo.Migrations.CreateAccountHolders do
  use Ecto.Migration

  def change do
    create table(:account_holders,
             primary_key: false,
             comment: "Account holders for onboarding screening with interested parties"
           ) do
      add :id, :binary_id, primary_key: true

      add :name, :string, comment: "Account holder name"

      add :type, :string, comment: "Account holder type: individual, business"

      # Embedded schemas stored as JSONB
      add :interested_companies, :map,
        comment: "List of interested companies (embedded schema with addresses and contact)"

      add :interested_individuals, :map,
        comment: "List of interested individuals (embedded schema with addresses and contact)"

      add :raw_body, :map, comment: "Raw request body data and metadata"

      # Multi-tenancy: tenant_id references tenants for RLS
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all),
        null: false,
        comment: "FK to tenant for multi-tenancy isolation (RLS)"

      timestamps(type: :utc_datetime_usec)
    end

    # Multi-tenancy indexes
    create index(:account_holders, [:tenant_id])
  end
end
