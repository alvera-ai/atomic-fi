defmodule AtomicFi.Repo.Migrations.CascadeLegalEntityChangeEventsOnLegalEntityDelete do
  @moduledoc """
  Drops the `:restrict` ON DELETE on
  `legal_entity_change_events.legal_entity_id` and replaces it with
  `:cascade`. Change events are by definition tied to the parent
  legal_entity's lifetime — they have no meaningful identity outside it —
  so they should be removed automatically when the parent is deleted.

  Before this change, deleting any legal_entity that had ever been updated
  (any update writes a change event row) returned 500 with
  `Ecto.ConstraintError: legal_entity_change_events_legal_entity_id_fkey`.

  Same fix applied to the parallel context FKs (account_holder_id,
  beneficial_owner_id) for symmetry.

  Uses raw `EXECUTE` because Ecto's `modify references(...)` does not
  reliably alter the existing `ON DELETE` rule across postgres versions —
  it ALTERs the column type rather than the constraint.

  Refs #17.
  """

  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE legal_entity_change_events
      DROP CONSTRAINT legal_entity_change_events_legal_entity_id_fkey,
      ADD  CONSTRAINT legal_entity_change_events_legal_entity_id_fkey
        FOREIGN KEY (legal_entity_id) REFERENCES legal_entities(id) ON DELETE CASCADE;
    """

    execute """
    ALTER TABLE legal_entity_change_events
      DROP CONSTRAINT legal_entity_change_events_account_holder_id_fkey,
      ADD  CONSTRAINT legal_entity_change_events_account_holder_id_fkey
        FOREIGN KEY (account_holder_id) REFERENCES account_holders(id) ON DELETE CASCADE;
    """

    execute """
    ALTER TABLE legal_entity_change_events
      DROP CONSTRAINT legal_entity_change_events_beneficial_owner_id_fkey,
      ADD  CONSTRAINT legal_entity_change_events_beneficial_owner_id_fkey
        FOREIGN KEY (beneficial_owner_id) REFERENCES beneficial_owners(id) ON DELETE CASCADE;
    """
  end

  def down do
    execute """
    ALTER TABLE legal_entity_change_events
      DROP CONSTRAINT legal_entity_change_events_legal_entity_id_fkey,
      ADD  CONSTRAINT legal_entity_change_events_legal_entity_id_fkey
        FOREIGN KEY (legal_entity_id) REFERENCES legal_entities(id) ON DELETE RESTRICT;
    """

    execute """
    ALTER TABLE legal_entity_change_events
      DROP CONSTRAINT legal_entity_change_events_account_holder_id_fkey,
      ADD  CONSTRAINT legal_entity_change_events_account_holder_id_fkey
        FOREIGN KEY (account_holder_id) REFERENCES account_holders(id) ON DELETE RESTRICT;
    """

    execute """
    ALTER TABLE legal_entity_change_events
      DROP CONSTRAINT legal_entity_change_events_beneficial_owner_id_fkey,
      ADD  CONSTRAINT legal_entity_change_events_beneficial_owner_id_fkey
        FOREIGN KEY (beneficial_owner_id) REFERENCES beneficial_owners(id) ON DELETE RESTRICT;
    """
  end
end
