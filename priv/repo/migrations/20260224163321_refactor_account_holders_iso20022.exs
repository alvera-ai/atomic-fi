defmodule AtomicFi.Repo.Migrations.RefactorAccountHoldersIso20022 do
  use Ecto.Migration

  def up do
    # Add new ISO 20022-aligned columns
    alter table(:account_holders) do
      # FK to legal_entity (identity record) — nullable during migration
      add :legal_entity_id,
          references(:legal_entities, type: :binary_id, on_delete: :restrict),
          comment: "FK to legal entity (all PII lives there)"

      add :external_id, :string, comment: "Upstream ID from payment rail (Stripe/JPMC/Moov)"

      add :holder_type, :string, comment: "Holder type: individual, organization"

      add :status, :string,
        default: "pending",
        null: false,
        comment: "Account holder status: pending, active, suspended, closed"

      add :kyc_status, :string,
        default: "not_started",
        null: false,
        comment: "KYC status: not_started, in_progress, approved, rejected, expired"

      add :risk_level, :string,
        default: "low",
        null: false,
        comment: "Risk level: low, medium, high, very_high, prohibited"

      add :enabled_currencies, {:array, :string},
        default: [],
        comment: "ISO 4217 currency codes enabled for this holder"

      add :account_holder_number, :string, comment: "Opaque internal account holder number"

      add :onboarded_at, :utc_datetime_usec,
        comment: "Timestamp when account holder was onboarded"

      add :last_reviewed_at, :utc_datetime_usec,
        comment: "Timestamp when account holder was last reviewed"
    end

    # Remove old columns that are superseded by LegalEntity
    alter table(:account_holders) do
      remove :name
      remove :type
      remove :interested_companies
      remove :interested_individuals
      remove :raw_body
    end

    # Indexes
    create index(:account_holders, [:legal_entity_id])
    create index(:account_holders, [:holder_type])
    create index(:account_holders, [:status])
    create index(:account_holders, [:kyc_status])

    create unique_index(:account_holders, [:external_id, :tenant_id],
             where: "external_id IS NOT NULL",
             name: :account_holders_external_id_tenant_id_unique
           )
  end

  def down do
    drop_if_exists index(:account_holders, [:legal_entity_id])
    drop_if_exists index(:account_holders, [:holder_type])
    drop_if_exists index(:account_holders, [:status])
    drop_if_exists index(:account_holders, [:kyc_status])

    drop_if_exists unique_index(:account_holders, [:external_id, :tenant_id],
                     name: :account_holders_external_id_tenant_id_unique
                   )

    alter table(:account_holders) do
      remove :legal_entity_id
      remove :external_id
      remove :holder_type
      remove :status
      remove :kyc_status
      remove :risk_level
      remove :enabled_currencies
      remove :account_holder_number
      remove :onboarded_at
      remove :last_reviewed_at
    end

    alter table(:account_holders) do
      add :name, :string
      add :type, :string
      add :interested_companies, :map
      add :interested_individuals, :map
      add :raw_body, :map
    end
  end
end
