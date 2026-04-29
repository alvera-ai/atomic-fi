defmodule AtomicFi.Repo.Migrations.CreateDecisions do
  use Ecto.Migration

  def change do
    create table(:decisions,
             primary_key: false,
             comment:
               "Screening decisions for account holder onboarding with sanctions list results"
           ) do
      add :id, :binary_id, primary_key: true

      add :overall_status, :string,
        null: false,
        comment: "Overall screening result: pass, potential_match, blocked"

      add :total_entities_screened, :integer,
        null: false,
        comment: "Total number of individuals and companies screened"

      add :entities_with_matches, :integer,
        null: false,
        comment: "Number of entities with potential matches"

      add :list_synced_at, :utc_datetime_usec,
        null: false,
        comment: "Timestamp when Watchman list info was retrieved"

      add :list_sources, :map, comment: "Watchman sources array with lastUpdated timestamps"

      add :raw_request, :map, comment: "Original request body from screening API call"

      # Embedded schemas stored as JSONB
      add :entity_decisions, :map,
        comment: "Array of entity screening results with Watchman data (embedded schema)"

      # Foreign keys
      add :account_holder_id,
          references(:account_holders, type: :binary_id, on_delete: :delete_all),
          null: false,
          comment: "FK to account_holder being screened"

      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all),
        null: false,
        comment: "FK to tenant for multi-tenancy isolation (RLS)"

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes
    create index(:decisions, [:account_holder_id])
    create index(:decisions, [:tenant_id])
    create index(:decisions, [:overall_status])
  end
end
