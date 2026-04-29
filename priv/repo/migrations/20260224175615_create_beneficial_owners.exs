defmodule AtomicFi.Repo.Migrations.CreateBeneficialOwners do
  use Ecto.Migration

  def change do
    create table(:beneficial_owners, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # FinCEN CDD Rule 31 CFR §1010.230 — ownership percentage (≥25% triggers CDD)
      add :ownership_pct, :float, comment: "Ownership percentage (≥25% triggers FinCEN CDD Rule)"

      # Control type: shareholder | director | officer | trustee
      add :control_type, :string,
        null: false,
        comment: "Control type: shareholder, director, officer, trustee"

      # Verification status: pending | verified | failed
      add :verification_status, :string,
        default: "pending",
        comment: "Verification status: pending, verified, failed"

      # Opaque external SoE identifier (nullable — not all systems provide this)
      add :beneficial_owner_number, :string, comment: "Opaque internal identifier"

      # FK to legal_entities — the identity record for this beneficial owner
      add :legal_entity_id,
          references(:legal_entities, on_delete: :delete_all, type: :binary_id),
          null: false,
          comment: "FK to legal entity (all PII lives there)"

      # FK to account_holders — the corporate entity being examined
      add :account_holder_id,
          references(:account_holders, on_delete: :delete_all, type: :binary_id),
          null: false,
          comment: "FK to the corporate account holder being examined"

      # Multi-tenancy: tenant_id for RLS
      add :tenant_id,
          references(:tenants, on_delete: :delete_all, type: :binary_id),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:beneficial_owners, [:control_type])
    create index(:beneficial_owners, [:verification_status])
    create index(:beneficial_owners, [:legal_entity_id])
    create index(:beneficial_owners, [:account_holder_id])

    # Partial unique on external SoE ID (only when present)
    create unique_index(:beneficial_owners, [:beneficial_owner_number],
             where: "beneficial_owner_number IS NOT NULL",
             name: :beneficial_owners_number_unique
           )

    # Natural key: one beneficial owner record per (company + person)
    create unique_index(:beneficial_owners, [:account_holder_id, :legal_entity_id],
             name: :beneficial_owners_account_holder_legal_entity_unique
           )
  end
end
