defmodule AlveraPhoenixTemplateServer.Repo.Migrations.AddCustomerIdAndRoleIdToApiKeys do
  use Ecto.Migration

  def change do
    # Add customer_id and role_id to api_keys
    # API keys now belong to ONE role (not many-to-many)
    alter table(:api_keys) do
      add :customer_id, references(:customers, type: :binary_id, on_delete: :delete_all),
        comment: "FK to customer for customer-scoped API keys (optional, nullable)"

      add :role_id, references(:roles, type: :binary_id, on_delete: :restrict),
        null: false,
        comment: "FK to role (API key has ONE role)"
    end

    create index(:api_keys, [:customer_id])
    create index(:api_keys, [:role_id])
  end
end
