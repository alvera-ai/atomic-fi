defmodule AtomicFi.Repo.Migrations.CreateRiskClassifications do
  use Ecto.Migration

  def change do
    create table(:risk_classifications, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_holder_id,
          references(:account_holders, type: :binary_id, on_delete: :restrict),
          null: false

      add :risk_level, :string, null: false
      add :classification_reason, :text, null: false

      add :effective_from, :date, null: false
      add :effective_until, :date, null: true

      add :is_active, :boolean, null: false, default: true

      add :classified_by_user_id,
          references(:users, type: :binary_id, on_delete: :nilify_all),
          null: true

      add :compliance_screening_id,
          references(:compliance_screenings, type: :binary_id, on_delete: :nilify_all),
          null: true

      add :notes, :text, null: true

      add :tenant_id,
          references(:tenants, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:risk_classifications, [:account_holder_id])
    create index(:risk_classifications, [:tenant_id])
    create index(:risk_classifications, [:risk_level])
    create index(:risk_classifications, [:is_active])
    create index(:risk_classifications, [:effective_from, :effective_until])
    create index(:risk_classifications, [:classified_by_user_id])
    create index(:risk_classifications, [:compliance_screening_id])

    # One active classification per AccountHolder per tenant
    create unique_index(:risk_classifications, [:account_holder_id, :tenant_id],
             where: "is_active = true",
             name: :risk_classifications_one_active_per_holder_tenant
           )
  end
end
