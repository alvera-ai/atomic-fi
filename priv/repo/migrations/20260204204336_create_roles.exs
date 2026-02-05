defmodule AlveraPhoenixTemplateServer.Repo.Migrations.CreateRoles do
  use Ecto.Migration

  def change do
    create table(:roles,
             primary_key: false,
             comment: "Authorization roles for users and API keys (e.g., admin, member, viewer)"
           ) do
      add :id, :binary_id, primary_key: true

      add :name, :string,
        null: false,
        comment: "Role name (unique within tenant, e.g., admin, member, viewer)"

      add :description, :string,
        comment: "Human-readable description of role purpose and permissions"

      add :metadata, :map,
        default: %{},
        comment: "Additional role configuration (permissions, features, limits)"

      # Multi-tenancy: tenant_id references tenants for RLS
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all),
        null: false,
        comment: "FK to tenant for multi-tenancy isolation (RLS)"

      timestamps(type: :utc_datetime_usec)
    end

    # Multi-tenancy indexes
    create index(:roles, [:tenant_id])
    create unique_index(:roles, [:name, :tenant_id])
  end
end
