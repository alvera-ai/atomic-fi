defmodule PaymentCompliancePlatform.Repo.Migrations.MoveListSyncedAtToSanctionsMatches do
  use Ecto.Migration

  def change do
    # list_synced_at and list_sources are match-level metadata — they record the
    # Watchman list state at the time a specific sanctions match was found, not at
    # the screening level. Moving them to sanctions_matches aligns with the same
    # pattern as blocklist_matches.blocklist_updated_at.

    alter table(:sanctions_matches) do
      add :list_synced_at, :utc_datetime_usec,
        comment: "Watchman list sync timestamp at the time this specific match was found"

      add :list_sources, :map,
        comment: "Watchman lists + version at the time this specific match was found"
    end

    alter table(:compliance_screenings) do
      remove :list_synced_at
      remove :list_sources
    end
  end
end
