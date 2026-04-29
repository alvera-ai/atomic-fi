defmodule AtomicFi.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Document type and identity
      add :document_type, :string, null: false
      add :name, :string, null: false
      add :description, :string

      # Status lifecycle
      add :status, :string, null: false, default: "draft"

      # Whether this is the primary document for this account_holder + name combination
      add :primary, :boolean, null: false, default: false

      # File reference (storage key — no S3 embed; external storage handled out-of-band)
      add :file_key, :string
      add :file_name, :string
      add :file_size, :integer
      add :content_type, :string

      # Optional opaque external document ID for SoE upsert matching
      add :document_number, :string

      # Metadata bag for arbitrary key-value pairs
      add :metadata, :map, default: %{}

      # MDM subject — AccountHolder is always the compliance subject
      add :account_holder_id,
          references(:account_holders, type: :binary_id, on_delete: :delete_all),
          null: false

      # Multi-tenancy: tenant_id references tenants for RLS
      add :tenant_id,
          references(:tenants, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:documents, [:account_holder_id])
    create index(:documents, [:tenant_id])
    create index(:documents, [:document_type])
    create index(:documents, [:status])
    create index(:documents, [:account_holder_id, :name])

    # At most one primary document per (account_holder_id, name) combination
    create unique_index(:documents, [:account_holder_id, :name],
             where: "\"primary\" = true",
             name: :documents_account_holder_name_primary_unique
           )

    # Optional external document number must be unique per tenant when present
    create unique_index(:documents, [:document_number, :tenant_id],
             where: "document_number IS NOT NULL",
             name: :documents_number_unique
           )

    # Trigger: enforce at least 1 primary exists before inserting a secondary
    execute(
      """
      CREATE OR REPLACE FUNCTION documents_check_primary_func()
      RETURNS TRIGGER AS $$
      BEGIN
        IF NEW."primary" = false THEN
          IF NOT EXISTS (
            SELECT 1 FROM documents
            WHERE account_holder_id = NEW.account_holder_id
              AND name = NEW.name
              AND "primary" = true
          ) THEN
            RAISE EXCEPTION 'documents_primary_required_before_secondary'
              USING ERRCODE = 'P0001';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION IF EXISTS documents_check_primary_func() CASCADE"
    )

    execute(
      """
      CREATE OR REPLACE TRIGGER documents_check_primary
      BEFORE INSERT OR UPDATE ON documents
      FOR EACH ROW EXECUTE PROCEDURE documents_check_primary_func();
      """,
      "DROP TRIGGER IF EXISTS documents_check_primary ON documents"
    )
  end
end
