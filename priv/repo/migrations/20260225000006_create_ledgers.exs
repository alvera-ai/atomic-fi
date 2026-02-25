defmodule PaymentCompliancePlatform.Repo.Migrations.CreateLedgers do
  use Ecto.Migration

  def change do
    create table(:ledgers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # FK to account_holders — MDM subject
      add :account_holder_id,
          references(:account_holders, type: :binary_id, on_delete: :restrict),
          null: false

      # ISO 4217 three-letter currency code — discriminator (one ledger per AH + currency)
      add :currency, :string, null: false, size: 3

      # Ledger lifecycle status
      add :status, :string, null: false, default: "active"

      # Opaque external SoE identifier (nullable — not PII; used for upsert identity)
      add :ledger_number, :string

      # RLS scope
      add :tenant_id,
          references(:tenants, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:ledgers, [:tenant_id])
    create index(:ledgers, [:account_holder_id])
    create index(:ledgers, [:status])

    # Natural key: one ledger per AccountHolder per currency
    create unique_index(:ledgers, [:account_holder_id, :currency],
             name: :ledgers_account_holder_id_currency_index
           )

    # Upsert key: ledger_number when present
    create unique_index(:ledgers, [:ledger_number],
             where: "ledger_number IS NOT NULL",
             name: :ledgers_ledger_number_unique
           )
  end
end
