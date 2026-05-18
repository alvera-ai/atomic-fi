defmodule AtomicFi.Repo.Migrations.SplitLegalEntityBeneficialOwnerSubjectTypes do
  use Ecto.Migration

  # Splits LegalEntity.subject_type's single :beneficial_owner value into
  # two: :account_holder_beneficial_owner and :counterparty_beneficial_owner.
  #
  # Today's `:beneficial_owner` cannot tell whether the BO is a UBO of the
  # host AccountHolder or of a Counterparty under that AH — both cases
  # collide on the same subject_type and rely on `legal_entities.account_holder_id`
  # as a tree-root partition (not a semantic ownership edge). The split
  # disambiguates LE-side: CP-BO LEs additionally set `counterparty_id`,
  # which makes "this CP's BOs" a clean LE-driven traversal:
  #
  #     CounterpartyContext.list_counterparties / preload :beneficial_owners
  #       through  [:counterparty_beneficial_owner_legal_entities, :beneficial_owner]
  #
  # Two schema-level adjustments are required:
  #
  #   1. The existing `legal_entities_counterparty_unique` partial unique
  #      index is too broad: it forbids ANY two LEs from sharing a
  #      `counterparty_id`. Once CP-BO LEs also stamp `counterparty_id`,
  #      the CP's own identity LE and its BO LEs would collide. Re-scope
  #      to subject_type = 'counterparty' so only the CP's own identity LE
  #      is uniqueness-scoped, not its BO LEs.
  #
  #   2. A CHECK constraint ties subject_type to which parent FKs must be
  #      set among (counterparty_id, beneficial_owner_id). `account_holder_id`
  #      is column-level NOT NULL on every LE row (see
  #      20260516000004_flip_legal_entity_fk_direction.exs) so the CHECK
  #      does not police it. The DB becomes the single source of truth for
  #      the (subject, parent-FK presence) invariant; the BO-LE changeset
  #      just derives subject_type from whether counterparty_id is
  #      supplied and lets the constraint validate.
  #
  # Code is not yet live in production — no data preservation.
  #
  # Forward-only.

  def change do
    drop index(:legal_entities, [:counterparty_id], name: :legal_entities_counterparty_unique)

    create unique_index(:legal_entities, [:counterparty_id],
             where: "subject_type = 'counterparty'",
             name: :legal_entities_counterparty_unique,
             comment: "1:1 — at most one identity LE per Counterparty (excludes CP-BO LEs)"
           )

    create constraint(:legal_entities, :legal_entities_subject_fk_consistency,
             check: """
               (subject_type = 'account_holder'
                  AND counterparty_id IS NULL
                  AND beneficial_owner_id IS NULL)
               OR
               (subject_type = 'counterparty'
                  AND counterparty_id IS NOT NULL
                  AND beneficial_owner_id IS NULL)
               OR
               (subject_type = 'account_holder_beneficial_owner'
                  AND counterparty_id IS NULL
                  AND beneficial_owner_id IS NOT NULL)
               OR
               (subject_type = 'counterparty_beneficial_owner'
                  AND counterparty_id IS NOT NULL
                  AND beneficial_owner_id IS NOT NULL)
             """
           )
  end
end
