defmodule AtomicFi.Repo.Migrations.CreateComplianceScreenings do
  use Ecto.Migration

  def change do
    # -------------------------------------------------------------------------
    # compliance_screenings — ISO 20022 auth:018 / camt:998
    # One row per entity per screening run.
    # -------------------------------------------------------------------------
    create table(:compliance_screenings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Screening scope (which lifecycle gate triggered the check)
      add :scope, :string,
        null: false,
        comment: "account_holder | counterparty | payment_account | transaction"

      # Screening type (which compliance check was performed)
      add :screening_type, :string,
        null: false,
        comment: "sanctions | pep | aml | adverse_media"

      # Overall screening outcome
      add :screening_status, :string,
        null: false,
        default: "pending",
        comment: "pending | pass | potential_match | blocked | escalated"

      # Confidence score (0.0–100.0, NULL if no Watchman call was made)
      add :screening_score, :decimal, comment: "Overall screening confidence score (0.0–100.0)"

      # Screened entity metadata
      add :screened_entity_type, :string,
        null: false,
        comment: "individual | company"

      add :screened_entity_name, :string,
        null: false,
        comment: "Full name or company name that was screened"

      add :match_count, :integer,
        default: 0,
        comment: "Total non-suppressed matches found across all child rows"

      add :screened_at, :utc_datetime_usec, comment: "When the screening engine ran"

      add :screening_rules, :string, comment: "Blocklist rule IDs that triggered (nullable)"

      # Sanctions sub-status (ISO 20022 auth:018 SanctionsCheckType)
      add :sanctions_screening_status, :string, comment: "cleared | pending | match | failed"

      add :sanctions_screening_date, :utc_datetime_usec

      # PEP fields
      add :pep_indicator, :boolean,
        default: false,
        comment: "Whether screened entity appears on a PEP list"

      add :pep_list_name, :string

      # AML fields (camt:998)
      add :aml_risk_score, :decimal
      add :aml_velocity_flag, :boolean, default: false
      add :aml_velocity_count, :integer
      add :aml_geographic_risk_flag, :boolean, default: false

      add :aml_high_risk_country, :string, comment: "ISO 3166-1 alpha-2 high-risk country code"

      # Entity-level false positive qualifier
      add :false_positive_qualifier, :string,
        default: "none",
        comment: "none | manual_override | auto_suppressed"

      # Manual review workflow
      add :manual_review_required, :boolean, default: false
      add :reviewed_at, :utc_datetime_usec
      add :reviewed_by_user_id, :binary_id
      add :review_notes, :string

      # Escalation (1–5)
      add :escalation_level, :integer

      # Watchman list metadata
      add :list_sources, :map, comment: "Watchman lists + version at time of screening"

      add :list_synced_at, :utc_datetime_usec,
        comment: "Watchman list sync timestamp at time of screening"

      # Opaque SoE identifier (nullable)
      add :compliance_screening_number, :string

      # Entity references
      add :account_holder_id,
          references(:account_holders, type: :binary_id, on_delete: :delete_all),
          null: false,
          comment: "FK to the MDM account holder subject"

      # Soft refs — tables not yet created; enforced at application layer
      add :counterparty_id, :binary_id
      add :payment_account_id, :binary_id
      add :transaction_id, :binary_id

      # Multi-tenancy RLS
      add :tenant_id,
          references(:tenants, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:compliance_screenings, [:account_holder_id])
    create index(:compliance_screenings, [:tenant_id])
    create index(:compliance_screenings, [:scope])
    create index(:compliance_screenings, [:screening_type])
    create index(:compliance_screenings, [:screening_status])
    create index(:compliance_screenings, [:screened_at])
    create index(:compliance_screenings, [:false_positive_qualifier])

    create unique_index(:compliance_screenings, [:compliance_screening_number],
             where: "compliance_screening_number IS NOT NULL",
             name: :compliance_screenings_number_unique
           )

    # -------------------------------------------------------------------------
    # sanctions_matches — one row per Watchman / OFAC hit
    # Watchman sub-objects (addresses, business, person, contact) stored as
    # typed JSONB embeds — structured without requiring separate tables.
    # -------------------------------------------------------------------------
    create table(:sanctions_matches, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :compliance_screening_id,
          references(:compliance_screenings, type: :binary_id, on_delete: :delete_all),
          null: false,
          comment: "FK to the parent compliance screening"

      add :matched_name, :string,
        null: false,
        comment: "Full name from the sanctions list entry"

      add :matched_entity_type, :string,
        comment: "Entity type from Watchman (individual, company, etc.)"

      add :match_score, :float,
        null: false,
        comment: "Watchman match confidence score (0.0–1.0)"

      add :sanctions_match_type, :string,
        default: "fuzzy",
        comment: "exact | fuzzy | ubo | entity"

      add :source_list, :string,
        null: false,
        comment: "Source list name (OFAC_SDN, EU_CONSOLIDATED, UN_SC)"

      add :source_id, :string,
        comment: "Watchman SDN entry ID — used for false-positive dedup across re-screenings"

      add :source_data, :map, comment: "Full Watchman payload"

      # Typed JSONB embeds for Watchman sub-objects
      add :addresses, :map,
        comment: "Normalized Watchman address entries (WatchmanAddress typed embeds)"

      add :business_data, :map,
        comment: "Normalized Watchman business block (WatchmanBusiness typed embed)"

      add :person_data, :map,
        comment: "Normalized Watchman person block (WatchmanPerson typed embed)"

      add :contact_data, :map,
        comment: "Normalized Watchman contact block (WatchmanContact typed embed)"

      # Per-match false positive qualifier
      add :false_positive_qualifier, :string,
        default: "none",
        comment: "none | manual_override | auto_suppressed"

      # Reviewer audit trail
      add :review_notes, :string
      add :reviewed_by_user_id, :binary_id
      add :reviewed_at, :utc_datetime_usec

      # Multi-tenancy RLS
      add :tenant_id,
          references(:tenants, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:sanctions_matches, [:compliance_screening_id])
    create index(:sanctions_matches, [:tenant_id])
    create index(:sanctions_matches, [:source_id])
    create index(:sanctions_matches, [:false_positive_qualifier])

    # -------------------------------------------------------------------------
    # blocklist_matches — one row per internal blocklist hit
    # Blocklist checks are fail-fast: if any match fires, Watchman is skipped.
    # -------------------------------------------------------------------------
    create table(:blocklist_matches, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :compliance_screening_id,
          references(:compliance_screenings, type: :binary_id, on_delete: :delete_all),
          null: false,
          comment: "FK to the parent compliance screening"

      add :matched_term, :string,
        null: false,
        comment: "The blocklist term that was matched"

      add :match_type, :string,
        null: false,
        comment: "exact | regex"

      add :scope, :string,
        null: false,
        comment: "first_name | last_name | company_name"

      add :reason, :string, comment: "Human-readable reason from the blocklist entry"

      add :blocklist_updated_at, :utc_datetime_usec,
        comment:
          "Blocklist last-refresh timestamp at screening time — allows re-evaluation of overrides after list updates"

      # Per-match false positive qualifier
      add :false_positive_qualifier, :string,
        default: "none",
        comment: "none | manual_override | auto_suppressed"

      # Reviewer audit trail
      add :review_notes, :string
      add :reviewed_by_user_id, :binary_id
      add :reviewed_at, :utc_datetime_usec

      # Multi-tenancy RLS
      add :tenant_id,
          references(:tenants, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:blocklist_matches, [:compliance_screening_id])
    create index(:blocklist_matches, [:tenant_id])
    create index(:blocklist_matches, [:false_positive_qualifier])
    create index(:blocklist_matches, [:scope])
    create index(:blocklist_matches, [:match_type])
  end
end
