defmodule PaymentCompliancePlatform.Repo.Migrations.AddCustomerIdToRoles do
  use Ecto.Migration

  def change do
    # Add customer_id to roles (nullable - for customer-scoped roles)
    alter table(:roles) do
      add :customer_id, references(:customers, type: :binary_id, on_delete: :delete_all),
        comment: "FK to customer for customer-scoped roles (optional, nullable)"
    end

    create index(:roles, [:customer_id])

    # Drop old unique index on [:name, :tenant_id]
    drop unique_index(:roles, [:name, :tenant_id])

    # Create new composite unique indexes with partial constraints
    # For customer roles: unique within customer
    create unique_index(:roles, [:name, :customer_id, :tenant_id],
             where: "customer_id IS NOT NULL",
             name: :roles_customer_unique_index
           )

    # For tenant roles: unique within tenant
    create unique_index(:roles, [:name, :tenant_id],
             where: "customer_id IS NULL",
             name: :roles_tenant_unique_index
           )
  end
end
