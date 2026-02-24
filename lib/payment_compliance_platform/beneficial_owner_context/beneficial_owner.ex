defmodule PaymentCompliancePlatform.BeneficialOwnerContext.BeneficialOwner do
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.AccountHolderContext.AccountHolder
  alias PaymentCompliancePlatform.LegalEntityContext.LegalEntity
  alias PaymentCompliancePlatform.TenantContext.Tenant

  @typedoc """
  Beneficial owner — links a corporate AccountHolder to each person/entity that
  owns or controls it (ISO 20022 / FinCEN CDD Rule 31 CFR §1010.230 / FATF Rec 24).

  ≥25% ownership triggers FinCEN CDD requirements. All PII lives in the linked LegalEntity.

  ## Attributes

  * `id` - UUID primary key
  * `account_holder_id` - FK to the corporate AccountHolder being examined
  * `legal_entity_id` - FK to LegalEntity (all PII / identity for the owner)
  * `ownership_pct` - Ownership percentage (≥25% triggers FinCEN CDD)
  * `control_type` - `shareholder` | `director` | `officer` | `trustee`
  * `verification_status` - `pending` | `verified` | `failed`
  * `beneficial_owner_number` - Opaque internal identifier
  * `tenant_id` - FK to tenant for multi-tenancy isolation (RLS)
  * `inserted_at` - Timestamp when record was created
  * `updated_at` - Timestamp when record was last updated
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [:id, :tenant_id, :account_holder_id, :control_type, :verification_status],
    sortable: [:id, :inserted_at, :updated_at, :ownership_pct, :control_type],
    default_limit: 20,
    max_limit: 100
  }

  # OpenAPI annotations
  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{type: :string, format: :uuid},
    key: :account_holder_id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid},
    key: :legal_entity_id
  )

  open_api_property(
    schema: %Schema{type: :number, nullable: true},
    key: :ownership_pct
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      enum: ["shareholder", "director", "officer", "trustee"]
    },
    key: :control_type
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: ["pending", "verified", "failed"]
    },
    key: :verification_status
  )

  open_api_property(
    schema: %Schema{type: :string, nullable: true},
    key: :beneficial_owner_number
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid},
    key: :tenant_id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", readOnly: true},
    key: :inserted_at
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", readOnly: true},
    key: :updated_at
  )

  open_api_schema(
    title: "BeneficialOwner",
    description:
      "Beneficial owner of a corporate account holder. " <>
        "≥25% ownership triggers FinCEN CDD Rule 31 CFR §1010.230 (FATF Rec 24). " <>
        "All PII lives in the linked LegalEntity.",
    required: [:account_holder_id, :legal_entity_id, :control_type],
    properties: [
      :id,
      :account_holder_id,
      :legal_entity_id,
      :ownership_pct,
      :control_type,
      :verification_status,
      :beneficial_owner_number,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "beneficial_owners" do
    belongs_to :account_holder, AccountHolder
    belongs_to :legal_entity, LegalEntity

    field :ownership_pct, :float

    field :control_type, Ecto.Enum, values: [:shareholder, :director, :officer, :trustee]

    field :verification_status, Ecto.Enum,
      values: [:pending, :verified, :failed],
      default: :pending

    field :beneficial_owner_number, :string

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(beneficial_owner, attrs) do
    beneficial_owner
    |> cast(attrs, [
      :account_holder_id,
      :legal_entity_id,
      :ownership_pct,
      :control_type,
      :verification_status,
      :beneficial_owner_number,
      :tenant_id
    ])
    |> validate_required([:account_holder_id, :legal_entity_id, :control_type, :tenant_id])
    |> validate_number(:ownership_pct, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:legal_entity_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:account_holder_id, :legal_entity_id],
      name: :beneficial_owners_account_holder_legal_entity_unique
    )
  end
end
