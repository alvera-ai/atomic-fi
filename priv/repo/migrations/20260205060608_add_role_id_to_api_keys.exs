defmodule AtomicFi.Repo.Migrations.AddRoleIdToApiKeys do
  use Ecto.Migration

  def change do
    # API keys belong to exactly one role.
    alter table(:api_keys) do
      add :role_id, references(:roles, type: :binary_id, on_delete: :restrict),
        null: false,
        comment: "FK to role (API key has ONE role)"
    end

    create index(:api_keys, [:role_id])
  end
end
