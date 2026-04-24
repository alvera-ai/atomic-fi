defmodule PaymentCompliancePlatform.Repo.Migrations.CreateCounterparties do
  use Ecto.Migration

  def change do
    create table(:counterparties, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # ISO 20022 <Dbtr>/<Cdtr> identity — the external payer/payee
      add :legal_entity_id,
          references(:legal_entities, on_delete: :delete_all, type: :binary_id),
          null: false,
          comment: "FK to legal entity (all PII for the external party)"

      # MDM subject FK — the internal account holder transacting with this counterparty
      add :account_holder_id,
          references(:account_holders, on_delete: :delete_all, type: :binary_id),
          null: false,
          comment: "FK to the internal account holder"

      # Relationship lifecycle state
      add :status, :string,
        null: false,
        default: "active",
        comment: "Lifecycle: active, suspended, blocked"

      # Opaque external SoE identifier (nullable — not all systems provide this)
      add :counterparty_number, :string, comment: "Opaque external SoE identifier"

      # Multi-tenancy: tenant_id for RLS
      add :tenant_id,
          references(:tenants, on_delete: :delete_all, type: :binary_id),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:counterparties, [:status])
    create index(:counterparties, [:legal_entity_id])
    create index(:counterparties, [:account_holder_id])

    # Partial unique on external SoE ID (only when present)
    create unique_index(:counterparties, [:counterparty_number],
             where: "counterparty_number IS NOT NULL",
             name: :counterparties_number_unique
           )

    # Natural key: one counterparty per (account_holder + legal_entity)
    create unique_index(:counterparties, [:account_holder_id, :legal_entity_id],
             name: :counterparties_account_holder_legal_entity_unique
           )
  end
end
