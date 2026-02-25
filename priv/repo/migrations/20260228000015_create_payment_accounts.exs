defmodule PaymentCompliancePlatform.Repo.Migrations.CreatePaymentAccounts do
  use Ecto.Migration

  def change do
    create table(:payment_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # ── Subject anchor (MDM) ─────────────────────────────────────────────
      add :account_holder_id,
          references(:account_holders, type: :binary_id, on_delete: :restrict),
          null: false

      # ── Optional links ───────────────────────────────────────────────────
      # legal_entity_id — PII anchor (holds sensitive account numbers out-of-band)
      add :legal_entity_id,
          references(:legal_entities, type: :binary_id, on_delete: :restrict),
          null: true

      # counterparty_id — external payer/payee link (FATF Rec 16 wire transfer)
      add :counterparty_id,
          references(:counterparties, type: :binary_id, on_delete: :restrict),
          null: true

      # ledger_account_id — which chart-of-accounts line this payment account maps to
      add :ledger_account_id,
          references(:ledger_accounts, type: :binary_id, on_delete: :restrict),
          null: true

      # ── Account metadata ─────────────────────────────────────────────────
      add :account_type, :string, null: false
      add :status, :string, null: false, default: "active"

      # ISO 4217 3-letter currency code (e.g. "USD", "EUR", "GBP")
      add :currency, :string, null: true

      # ── Bank / card details (PCI-DSS 4.0 sensitive fields) ────────────────
      # Store only what is needed for compliance identification; raw PANs should
      # be tokenised by the calling orchestration layer before writing here.
      add :account_number, :string, null: true
      add :routing_number, :string, null: true
      add :iban, :string, null: true
      add :swift_bic, :string, null: true
      add :bank_name, :string, null: true
      # card_pan — store last-4 or tokenised value only (never full PAN)
      add :card_pan, :string, null: true

      # ── Identifiers ──────────────────────────────────────────────────────
      # payment_account_number — opaque internal account number
      add :payment_account_number, :string, null: true

      # payment_account_external_id — caller-supplied SoE upsert key
      add :payment_account_external_id, :string, null: true

      # ── Multi-tenancy ────────────────────────────────────────────────────
      add :tenant_id,
          references(:tenants, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    # ── Indexes ──────────────────────────────────────────────────────────────
    create index(:payment_accounts, [:account_holder_id])
    create index(:payment_accounts, [:legal_entity_id])
    create index(:payment_accounts, [:counterparty_id])
    create index(:payment_accounts, [:ledger_account_id])
    create index(:payment_accounts, [:tenant_id])
    create index(:payment_accounts, [:status])

    # Unique external ID per tenant (sparse — only enforced when non-null)
    create unique_index(:payment_accounts, [:payment_account_external_id, :tenant_id],
             where: "payment_account_external_id IS NOT NULL",
             name: :payment_accounts_external_id_tenant_unique
           )

    # Unique internal account number per tenant (sparse)
    create unique_index(:payment_accounts, [:payment_account_number, :tenant_id],
             where: "payment_account_number IS NOT NULL",
             name: :payment_accounts_number_tenant_unique
           )
  end
end
