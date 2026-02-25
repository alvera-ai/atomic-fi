defmodule PaymentCompliancePlatform.Repo.Migrations.AddLatestChangeEventToLegalEntities do
  use Ecto.Migration

  def change do
    # Add nullable FK on legal_entities pointing to the most recent LegalEntityChangeEvent.
    # This FK is maintained by the DB trigger below — never written directly by application code.
    # on_delete: :nilify_all — if the change event row is deleted, the FK is set to NULL.
    alter table(:legal_entities) do
      add :latest_change_event_id,
          references(:legal_entity_change_events, type: :binary_id, on_delete: :nilify_all),
          null: true,
          comment:
            "FK to the most recent LegalEntityChangeEvent for this entity. " <>
              "Maintained by DB trigger after each change event insert. Never written directly."
    end

    create index(:legal_entities, [:latest_change_event_id])

    # ── Trigger: after inserting a change event ────────────────────────────────────────
    # 1. Updates legal_entities.latest_change_event_id to point to the new event row.
    # 2. Flips the change event's event_status from "pending" to "recorded".
    # The WHEN clause ensures this only fires for new events inserted with status "pending"
    # (i.e., auto-created via prepare_changes on update_legal_entity, not manual API inserts
    # with a different initial status).
    execute(
      """
      CREATE OR REPLACE FUNCTION update_legal_entity_after_change_event()
      RETURNS TRIGGER AS $$
      BEGIN
        -- Update the legal_entity to point to this new change event
        UPDATE legal_entities
        SET latest_change_event_id = NEW.id,
            updated_at = (NOW() AT TIME ZONE 'UTC')
        WHERE id = NEW.legal_entity_id;

        -- Flip event_status from pending to recorded
        UPDATE legal_entity_change_events
        SET event_status = 'recorded',
            updated_at = (NOW() AT TIME ZONE 'UTC')
        WHERE id = NEW.id;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION IF EXISTS update_legal_entity_after_change_event CASCADE"
    )

    execute(
      """
      CREATE TRIGGER legal_entity_change_event_after_insert
        AFTER INSERT ON legal_entity_change_events
        FOR EACH ROW
        WHEN (NEW.event_status = 'pending')
        EXECUTE FUNCTION update_legal_entity_after_change_event()
      """,
      "DROP TRIGGER IF EXISTS legal_entity_change_event_after_insert ON legal_entity_change_events"
    )
  end
end
