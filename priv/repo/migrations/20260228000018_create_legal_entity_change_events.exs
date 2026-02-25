defmodule PaymentCompliancePlatform.Repo.Migrations.CreateLegalEntityChangeEvents do
  use Ecto.Migration

  def change do
    create table(:legal_entity_change_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # ── Subject anchor (identity layer — covers AccountHolder and BeneficialOwner) ─
      # acmt:006 references the LegalEntity as the identity subject being modified
      add :legal_entity_id,
          references(:legal_entities, type: :binary_id, on_delete: :restrict),
          null: false

      # ── Context FKs (nullable — event may belong to one or both threads) ──────────
      add :account_holder_id,
          references(:account_holders, type: :binary_id, on_delete: :restrict),
          null: true

      add :beneficial_owner_id,
          references(:beneficial_owners, type: :binary_id, on_delete: :restrict),
          null: true

      # ── Event classification ──────────────────────────────────────────────────────
      # acmt:006 MdcnCd (Modification Code) mapped to internal event type
      add :event_type, :string, null: false

      # Channel through which the modification request was received
      add :change_channel, :string, null: false

      # Lifecycle status of this change event
      add :event_status, :string, null: false, default: "pending"

      # ── ISO 20022 acmt references ─────────────────────────────────────────────────
      # acmt:006 MsgId — upsert deduplication key (unique per tenant when set)
      add :acmt_instruction_id, :string, null: true

      # acmt:002 MsgId — confirmation message reference (populated once confirmed)
      add :acmt_confirmation_id, :string, null: true

      # ── Changeset diff (JSONB) ────────────────────────────────────────────────────
      # System-generated on update_legal_entity via prepare_changes/2.
      # changes: %{"field_name" => [previous_value, new_value]} — JSON-safe primitives
      # previous_state: full LegalEntity snapshot before this change was applied
      # event_status transitions: pending → recorded (flipped by DB trigger after insert)
      add :changes, :map, null: true
      add :previous_state, :map, null: true

      # ── Multi-tenancy (RLS) ───────────────────────────────────────────────────────
      add :tenant_id,
          references(:tenants, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    # ── Indexes ───────────────────────────────────────────────────────────────────────
    create index(:legal_entity_change_events, [:legal_entity_id])
    create index(:legal_entity_change_events, [:account_holder_id])
    create index(:legal_entity_change_events, [:beneficial_owner_id])
    create index(:legal_entity_change_events, [:tenant_id])
    create index(:legal_entity_change_events, [:event_type])
    create index(:legal_entity_change_events, [:event_status])
    create index(:legal_entity_change_events, [:change_channel])

    # Sparse unique index on acmt_instruction_id per tenant — dedup for acmt:006 messages
    create unique_index(:legal_entity_change_events, [:acmt_instruction_id, :tenant_id],
             where: "acmt_instruction_id IS NOT NULL",
             name: :legal_entity_change_events_acmt_instruction_tenant_unique
           )
  end
end
