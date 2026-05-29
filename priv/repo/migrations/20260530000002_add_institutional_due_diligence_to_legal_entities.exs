defmodule AtomicFi.Repo.Migrations.AddInstitutionalDueDiligenceToLegalEntities do
  use Ecto.Migration

  def change do
    alter table(:legal_entities) do
      add :institution_type, :string
      add :has_physical_presence, :boolean
      add :jurisdiction_cooperative, :boolean
    end

    create index(:legal_entities, [:institution_type])
  end
end
