defmodule PaymentCompliancePlatform.Repo.Migrations.CreateObanJobs do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 12, prefix: "oban", create_schema: true)
  end

  def down do
    Oban.Migration.down(version: 1, prefix: "oban")
  end
end
