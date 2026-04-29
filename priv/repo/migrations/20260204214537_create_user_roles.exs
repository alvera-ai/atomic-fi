defmodule AtomicFi.Repo.Migrations.CreateUserRoles do
  use Ecto.Migration

  def change do
    create table(:user_roles,
             primary_key: false,
             comment: "Join table mapping users to roles for authorization"
           ) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true,
        comment: "FK to user being assigned the role"

      add :role_id, references(:roles, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true,
        comment: "FK to role being assigned to the user"
    end

    create index(:user_roles, [:user_id])
    create index(:user_roles, [:role_id])
  end
end
