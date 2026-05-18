defmodule AtomicFi.Repo.Migrations.UpdateObanJobsToV14 do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 14, prefix: "oban")
  end

  def down do
    Oban.Migration.down(version: 12, prefix: "oban")
  end
end
