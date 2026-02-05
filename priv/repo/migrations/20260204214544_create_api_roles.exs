defmodule AlveraPhoenixTemplateServer.Repo.Migrations.CreateApiRoles do
  use Ecto.Migration

  def change do
    create table(:api_roles,
             primary_key: false,
             comment: "Join table mapping API keys to roles for authorization"
           ) do
      add :api_key_id, references(:api_keys, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true,
        comment: "FK to API key being assigned the role"

      add :role_id, references(:roles, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true,
        comment: "FK to role being assigned to the API key"
    end

    create unique_index(:api_roles, [:api_key_id, :role_id])
    create index(:api_roles, [:role_id])
  end
end
