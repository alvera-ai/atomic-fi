defmodule PaymentCompliancePlatform.Repo.Migrations.CreateLegalEntities do
  use Ecto.Migration

  def change do
    # ── legal_entities ──────────────────────────────────────────────────────────
    create table(:legal_entities,
             primary_key: false,
             comment:
               "Shared identity records for individuals and businesses. " <>
                 "Separates PII from operational data per ISO 20022 acmt:007 + FATF CDD. " <>
                 "Referenced by account_holders, beneficial_owners, and other domain entities."
           ) do
      add :id, :binary_id, primary_key: true

      # ISO 20022 entity classification
      # individual | business
      add :legal_entity_type, :string,
        null: false,
        comment: "ISO 20022 entity classification: individual | business"

      # corporation | llc | non_profit | partnership | sole_proprietorship | trust | government
      add :legal_structure, :string,
        comment:
          "Legal structure for business entities: corporation | llc | non_profit | " <>
            "partnership | sole_proprietorship | trust | government"

      # Industry-specific MDM subject role for payment_risk domain
      # account_holder | beneficial_owner | nil (other industries)
      add :subject_type, :string,
        comment:
          "MDM subject role in payment_risk domain: account_holder | beneficial_owner. " <>
            "Null for other industries."

      # Business identity fields
      add :business_name, :string, comment: "Legal registered name of the business entity"

      add :doing_business_as_names, {:array, :string},
        default: [],
        comment: "Array of DBA (doing business as) names for the entity"

      add :date_formed, :date, comment: "Date of incorporation or formation for business entities"

      add :website, :string, comment: "Business website URL"

      # Individual identity fields (PII)
      add :first_name, :string, comment: "Legal first name of the individual"

      add :middle_name, :string, comment: "Legal middle name of the individual"

      add :last_name, :string, comment: "Legal last name of the individual"

      add :prefix, :string, comment: "Name prefix (Mr., Ms., Dr., etc.) — non-PII honorific"

      add :suffix, :string, comment: "Name suffix (Jr., Sr., III, etc.)"

      add :preferred_name, :string,
        comment: "Preferred or common name (may differ from legal name)"

      add :date_of_birth, :date,
        comment: "Date of birth for individual entities (FATF CDD requirement)"

      # Non-PII identity fields
      add :citizenship_country, :string,
        comment: "ISO 3166-1 alpha-2 country code for citizenship (not PII — categorical)"

      add :politically_exposed_person, :boolean,
        comment: "FATF PEP flag — whether the individual is a politically exposed person"

      # Multi-tenancy: tenant_id references tenants for RLS
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all),
        null: false,
        comment: "FK to tenant for multi-tenancy isolation (RLS)"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:legal_entities, [:tenant_id])
    create index(:legal_entities, [:legal_entity_type])
    create index(:legal_entities, [:citizenship_country])
    create index(:legal_entities, [:politically_exposed_person])

    # ── legal_entity_addresses ───────────────────────────────────────────────────
    create table(:legal_entity_addresses,
             primary_key: false,
             comment:
               "One-to-many addresses per legal entity. Supports multiple address types per entity."
           ) do
      add :id, :binary_id, primary_key: true

      add :legal_entity_id,
          references(:legal_entities, on_delete: :delete_all, type: :binary_id),
          null: false,
          comment: "FK to legal_entities (cascading delete)"

      # business | mailing | residential | po_box | other
      add :address_types, {:array, :string},
        null: false,
        default: [],
        comment: "Address types: business | mailing | residential | po_box | other"

      add :primary, :boolean,
        null: false,
        default: false,
        comment: "Whether this is the primary address for the entity"

      add :line1, :string, comment: "Street address line 1"

      add :line2, :string, comment: "Street address line 2 (apartment, suite, etc.)"

      add :locality, :string, comment: "City or locality"

      add :region, :string, comment: "State, province, or region"

      add :postal_code, :string, comment: "Postal or ZIP code"

      add :country, :string, comment: "ISO 3166-1 alpha-2 country code"

      # Multi-tenancy: tenant_id references tenants for RLS
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all),
        null: false,
        comment: "FK to tenant for multi-tenancy isolation (RLS)"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:legal_entity_addresses, [:legal_entity_id])
    create index(:legal_entity_addresses, [:tenant_id])
    create index(:legal_entity_addresses, [:country])

    # ── legal_entity_phone_numbers ───────────────────────────────────────────────
    create table(:legal_entity_phone_numbers,
             primary_key: false,
             comment: "One-to-many phone numbers per legal entity. Stored in E.164 format."
           ) do
      add :id, :binary_id, primary_key: true

      add :legal_entity_id,
          references(:legal_entities, on_delete: :delete_all, type: :binary_id),
          null: false,
          comment: "FK to legal_entities (cascading delete)"

      add :phone_number, :string, comment: "Phone number in E.164 format (e.g., +12125551234)"

      # Multi-tenancy: tenant_id references tenants for RLS
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all),
        null: false,
        comment: "FK to tenant for multi-tenancy isolation (RLS)"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:legal_entity_phone_numbers, [:legal_entity_id])
    create index(:legal_entity_phone_numbers, [:tenant_id])

    # ── legal_entity_identifications ─────────────────────────────────────────────
    create table(:legal_entity_identifications,
             primary_key: false,
             comment:
               "One-to-many identity documents per legal entity per FATF CDD requirements. " <>
                 "Unique per (legal_entity_id, id_type)."
           ) do
      add :id, :binary_id, primary_key: true

      add :legal_entity_id,
          references(:legal_entities, on_delete: :delete_all, type: :binary_id),
          null: false,
          comment: "FK to legal_entities (cascading delete)"

      # us_ssn | us_ein | us_itin | passport | driver_license | national_id | lei | tax_id
      add :id_type, :string,
        null: false,
        comment:
          "Document type: us_ssn | us_ein | us_itin | passport | " <>
            "driver_license | national_id | lei | tax_id"

      # Namespace URI — FHIR Identifier.system / watchman source_id pattern
      # e.g. "urn:oid:2.16.840.1.113883.4.1" (SSN), "https://www.gleif.org/lei"
      add :uri, :string,
        comment:
          "Namespace URI for the identifier system (FHIR Identifier.system pattern). " <>
            "e.g. urn:oid:2.16.840.1.113883.4.1 for SSN, https://www.gleif.org/lei for LEI"

      add :id_number, :string,
        comment: "The actual identification number (PII — SSN, passport number, EIN, etc.)"

      add :issuing_country, :string,
        comment: "ISO 3166-1 alpha-2 country code of the issuing authority"

      add :issuing_region, :string,
        comment: "State or region of the issuing authority (for driver licenses, etc.)"

      add :expiration_date, :date, comment: "Expiration date of the identity document"

      # Multi-tenancy: tenant_id references tenants for RLS
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all),
        null: false,
        comment: "FK to tenant for multi-tenancy isolation (RLS)"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:legal_entity_identifications, [:legal_entity_id])
    create index(:legal_entity_identifications, [:tenant_id])
    create index(:legal_entity_identifications, [:id_type])

    create unique_index(:legal_entity_identifications, [:legal_entity_id, :id_type],
             name: :legal_entity_identifications_entity_id_type_unique
           )
  end
end
