defmodule AtomicFi.Repo.Migrations.FlipLegalEntityFkDirection do
  use Ecto.Migration

  # Flips the AH/CP/BO ↔ LegalEntity FK direction.
  #
  # Before (atomic-fi pre-flip):
  #
  #   account_holders.legal_entity_id  → legal_entities.id    (AH owns the FK)
  #   counterparties.legal_entity_id   → legal_entities.id    (CP owns the FK)
  #   beneficial_owners.legal_entity_id→ legal_entities.id    (BO owns the FK)
  #
  # After (this migration, platform-shaped):
  #
  #   legal_entities.account_holder_id   → account_holders.id    (always set — AH rollup)
  #   legal_entities.counterparty_id     → counterparties.id     (set when subject_type=:counterparty)
  #   legal_entities.beneficial_owner_id → beneficial_owners.id  (set when subject_type=:beneficial_owner)
  #
  # The AH-uniform `account_holder_id` is NOT NULL on every LE row — for
  # compliance reporting ("all PII tied to AH X") via a single indexed
  # lookup. A LE owned by a CP under that AH carries both columns: its
  # parent CP via `counterparty_id` AND the host AH via `account_holder_id`.
  #
  # 1:1 invariant per parent enforced by partial unique indexes per owner.
  #
  # Code is not yet live in production — no data preservation.
  #
  # Forward-only. Schema rollback would require re-establishing the
  # `legal_entity_id` columns on AH/CP/BO, which we do not support.

  def change do
    # ── 1. Add the three parent FKs to legal_entities ─────────────────────
    alter table(:legal_entities) do
      add :account_holder_id,
          references(:account_holders, on_delete: :delete_all, type: :binary_id),
          null: false,
          comment:
            "AH this LE rolls up to — always set, including on CP-owned and " <>
              "BO-owned LEs. Enables single-indexed 'all PII under AH X' compliance reporting."

      add :counterparty_id,
          references(:counterparties, on_delete: :delete_all, type: :binary_id),
          null: true,
          comment: "FK to counterparties — set when subject_type = :counterparty (cascade delete)"

      add :beneficial_owner_id,
          references(:beneficial_owners, on_delete: :delete_all, type: :binary_id),
          null: true,
          comment:
            "FK to beneficial_owners — set when subject_type = :beneficial_owner (cascade delete)"
    end

    # ── 2. Drop the now-obsolete legal_entity_id columns ──────────────────
    alter table(:account_holders) do
      remove :legal_entity_id, references(:legal_entities, type: :binary_id), null: false
    end

    alter table(:counterparties) do
      remove :legal_entity_id, references(:legal_entities, type: :binary_id), null: false
    end

    alter table(:beneficial_owners) do
      remove :legal_entity_id, references(:legal_entities, type: :binary_id), null: false
    end

    # ── 3. Per-parent partial unique indexes — 1:1 LE per parent ──────────
    create unique_index(:legal_entities, [:account_holder_id],
             where: "subject_type = 'account_holder'",
             name: :legal_entities_account_holder_unique,
             comment: "1:1 — at most one identity LE per AccountHolder"
           )

    create unique_index(:legal_entities, [:counterparty_id],
             where: "counterparty_id IS NOT NULL",
             name: :legal_entities_counterparty_unique,
             comment: "1:1 — at most one identity LE per Counterparty"
           )

    create unique_index(:legal_entities, [:beneficial_owner_id],
             where: "beneficial_owner_id IS NOT NULL",
             name: :legal_entities_beneficial_owner_unique,
             comment: "1:1 — at most one identity LE per BeneficialOwner"
           )

    create index(:legal_entities, [:counterparty_id],
             where: "counterparty_id IS NOT NULL",
             comment: "Lookup LE by owning Counterparty"
           )

    create index(:legal_entities, [:beneficial_owner_id],
             where: "beneficial_owner_id IS NOT NULL",
             comment: "Lookup LE by owning BeneficialOwner"
           )
  end
end
