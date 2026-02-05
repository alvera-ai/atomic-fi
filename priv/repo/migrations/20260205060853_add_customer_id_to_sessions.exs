defmodule AlveraPhoenixTemplateServer.Repo.Migrations.AddCustomerIdToSessions do
  use Ecto.Migration

  def change do
    # Add customer_id to sessions (nullable - for customer-scoped RLS)
    alter table(:sessions) do
      add :customer_id, references(:customers, type: :binary_id, on_delete: :nilify_all),
        comment: "FK to customer for customer-scoped RLS (optional, nullable)"
    end

    create index(:sessions, [:customer_id])
  end
end
