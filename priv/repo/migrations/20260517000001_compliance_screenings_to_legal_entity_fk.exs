defmodule AtomicFi.Repo.Migrations.ComplianceScreeningsToLegalEntityFk do
  use Ecto.Migration

  # Collapses the polymorphic subject FKs on compliance_screenings into a single
  # legal_entity_id anchor (party screening) alongside the existing
  # payment_account_id anchor (instrument screening). Drops the dead
  # transaction_id soft ref — IP/VPN/GeoIP signals are not "screenings" in the
  # rich-evidence sense (no match score, no list, no FP workflow); they will
  # land as derived columns on the transactions table in a future change
  # (scenarios #16/#17 in guides/use-cases.md).
  #
  # BEFORE                                  AFTER
  # ──────                                  ─────
  # account_holder_id    (NOT NULL FK)      legal_entity_id     party (PII)
  # beneficial_owner_id  (soft ref)         payment_account_id  instrument
  # counterparty_id      (soft ref)
  # payment_account_id   (soft ref)
  # transaction_id       (soft ref)         CHECK exactly_one(
  #                                            legal_entity_id,
  #                                            payment_account_id)
  #
  # Party screening already runs against a %LegalEntity{} in
  # `ScreeningEngine.Default.screen_party/3` (the Watchman call), so the result
  # row anchoring to LE matches the actual write path. Three subject FKs
  # collapsing to one removes the rule-side disambiguation burden.
  #
  # No backfill — code is not live in production and corpus.validate runs in an
  # isolated `atomic_fi_corpus` schema. Forward-only.

  def change do
    # ── 1. Add legal_entity_id (party anchor) ──────────────────────────
    alter table(:compliance_screenings) do
      add :legal_entity_id,
          references(:legal_entities, type: :binary_id, on_delete: :delete_all),
          null: true,
          comment:
            "Party-screening anchor — PII subject. " <>
              "Mutually exclusive with payment_account_id (CHECK constraint)."
    end

    # ── 2. Drop legacy subject FKs + dead txn ref ──────────────────────
    drop index(:compliance_screenings, [:account_holder_id])

    alter table(:compliance_screenings) do
      remove :account_holder_id,
             references(:account_holders, type: :binary_id, on_delete: :delete_all),
             null: false

      remove :beneficial_owner_id, :binary_id
      remove :counterparty_id, :binary_id
      remove :transaction_id, :binary_id
    end

    # ── 3. Indexes for the new shape ───────────────────────────────────
    create index(:compliance_screenings, [:legal_entity_id], where: "legal_entity_id IS NOT NULL")

    create index(:compliance_screenings, [:payment_account_id],
             where: "payment_account_id IS NOT NULL"
           )

    # ── 4. CHECK exactly one anchor is set ─────────────────────────────
    create constraint(:compliance_screenings, :compliance_screenings_exactly_one_anchor,
             check: """
             (CASE WHEN legal_entity_id    IS NOT NULL THEN 1 ELSE 0 END)
             + (CASE WHEN payment_account_id IS NOT NULL THEN 1 ELSE 0 END) = 1
             """
           )
  end
end
