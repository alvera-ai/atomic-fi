defmodule PaymentCompliancePlatform.Repo.Migrations.CreateKycRequirements do
  use Ecto.Migration

  def change do
    create table(:kyc_requirements, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # FATF scope — which party type this requirement applies to
      # account_holder (Rec 10 CDD), counterparty (Rec 19 EDD),
      # payment_account (Rec 16 wire), beneficial_owner (Rec 24 UBO)
      add :scope, :string, null: false

      # Requirement type — what document or action is required
      add :requirement_type, :string, null: false

      # KYC verification state (default: pending)
      add :status, :string, null: false, default: "pending"

      # Optional compliance deadline
      add :deadline, :date

      # Opaque external SoE identifier (nullable — not all systems provide this)
      add :kyc_requirement_number, :string

      # Required FK to account_holders — MDM subject (the entity under examination)
      add :account_holder_id,
          references(:account_holders, on_delete: :delete_all, type: :binary_id),
          null: false

      # Required FK to legal_entities — the identity being verified.
      # Resolves the correct party regardless of scope:
      # :account_holder → AH's own LegalEntity
      # :beneficial_owner → BO's LegalEntity
      # :counterparty → Counterparty's LegalEntity
      add :legal_entity_id,
          references(:legal_entities, on_delete: :delete_all, type: :binary_id),
          null: false

      # Optional link to submitted document (no FK — doc may not yet exist)
      add :document_id, :binary_id

      add :tenant_id,
          references(:tenants, on_delete: :delete_all, type: :binary_id),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:kyc_requirements, [:scope])
    create index(:kyc_requirements, [:requirement_type])
    create index(:kyc_requirements, [:status])
    create index(:kyc_requirements, [:account_holder_id])
    create index(:kyc_requirements, [:legal_entity_id])
    create index(:kyc_requirements, [:tenant_id])

    # Partial unique on external SoE ID (only when present)
    create unique_index(:kyc_requirements, [:kyc_requirement_number, :tenant_id],
             where: "kyc_requirement_number IS NOT NULL",
             name: :kyc_requirements_number_unique
           )

    # Natural key: one requirement per (account_holder + legal_entity + scope + type) per tenant
    create unique_index(
             :kyc_requirements,
             [:account_holder_id, :legal_entity_id, :scope, :requirement_type],
             name: :kyc_requirements_identity_unique
           )
  end
end
