defmodule PaymentCompliancePlatform.Repo.Migrations.CreateApiKeys do
  use Ecto.Migration

  def change do
    create table(:api_keys,
             primary_key: false,
             comment: "API keys for programmatic access with role-based permissions"
           ) do
      add :id, :binary_id, primary_key: true

      add :name, :string,
        null: false,
        comment: "Human-readable name for the API key (e.g., Production App, CI/CD)"

      add :key_hash, :binary,
        null: false,
        comment: "Cryptographic hash of the API key for fast validation queries"

      add :key_value, :binary,
        null: false,
        comment: "Encrypted API key value (for display in UI, encrypted via Cloak)"

      add :last_used_at, :utc_datetime_usec,
        comment: "Timestamp of the last successful API request using this key"

      # Multi-tenancy: tenant_id references tenants for RLS
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all),
        null: false,
        comment: "FK to tenant for multi-tenancy isolation (RLS)"

      timestamps(type: :utc_datetime_usec)
    end

    # Multi-tenancy indexes
    create index(:api_keys, [:tenant_id])
  end
end
