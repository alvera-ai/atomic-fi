defmodule PaymentCompliancePlatform.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users,
             primary_key: false,
             comment: "User accounts with email authentication and tenant association"
           ) do
      add :id, :binary_id, primary_key: true

      add :email, :string,
        null: false,
        comment: "User email address (unique within tenant)"

      add :hashed_password, :string, comment: "Bcrypt-hashed password for authentication"

      add :confirmed_at, :utc_datetime_usec,
        comment: "Timestamp when user confirmed their email address"

      # Multi-tenancy: tenant_id references tenants for RLS
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all),
        null: false,
        comment: "FK to tenant for multi-tenancy isolation (RLS)"

      timestamps(type: :utc_datetime_usec)
    end

    # Multi-tenancy indexes
    create index(:users, [:tenant_id])
    create unique_index(:users, [:email, :tenant_id])
  end
end
