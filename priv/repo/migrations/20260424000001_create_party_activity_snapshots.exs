defmodule AtomicFi.Repo.Migrations.CreatePartyActivitySnapshots do
  use Ecto.Migration

  def change do
    create table(:party_activity_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_holder_id,
          references(:account_holders, type: :binary_id, on_delete: :restrict),
          null: false

      add :period_type, :string, null: false

      add :period_start, :date, null: false
      add :period_end, :date, null: false

      add :kyc_status_at_start, :string, null: true
      add :kyc_status_at_end, :string, null: true

      add :risk_level_at_start, :string, null: true
      add :risk_level_at_end, :string, null: true

      add :total_screenings, :integer, null: false, default: 0
      add :screening_hits, :integer, null: false, default: 0

      add :transaction_count, :integer, null: false, default: 0
      add :total_debit_amount, :bigint, null: false, default: 0
      add :total_credit_amount, :bigint, null: false, default: 0
      add :high_risk_transaction_count, :integer, null: false, default: 0

      add :sar_indicator, :boolean, null: false, default: false

      add :notes, :text, null: true

      add :tenant_id,
          references(:tenants, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:party_activity_snapshots, [:account_holder_id])
    create index(:party_activity_snapshots, [:tenant_id])
    create index(:party_activity_snapshots, [:period_type])
    create index(:party_activity_snapshots, [:period_start, :period_end])
    create index(:party_activity_snapshots, [:sar_indicator])

    create index(:party_activity_snapshots, [:account_holder_id, :period_type, :period_start])

    create unique_index(
             :party_activity_snapshots,
             [:account_holder_id, :period_type, :period_start, :tenant_id],
             name: :party_activity_snapshots_holder_period_tenant_unique
           )
  end
end
