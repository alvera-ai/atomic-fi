defmodule PaymentCompliancePlatform.KycRequirementContext.KycRequirement do
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.AccountHolderContext.AccountHolder
  alias PaymentCompliancePlatform.LegalEntityContext.LegalEntity
  alias PaymentCompliancePlatform.TenantContext.Tenant

  @typedoc """
  KYC requirement — one row per verification action at a given FATF scope.

  ## FATF Scope Classification

  * `:account_holder` — CDD (FATF Rec 10); gates AccountHolder activation
  * `:counterparty` — EDD (FATF Rec 19); gates Counterparty activation
  * `:payment_account` — wire transfer (FATF Rec 16); gates PaymentAccount
  * `:beneficial_owner` — UBO transparency (FATF Rec 24); gates UBO chain

  ## Two-Field Anchor Pattern

  `account_holder_id` is always the MDM subject. `legal_entity_id` is the
  identity being verified — the AccountHolder's own LegalEntity, a
  BeneficialOwner's LegalEntity, or a Counterparty's LegalEntity.

  ## Upsert Strategy

  Dual-key: match by `kyc_requirement_number` first (opaque SoE external ID),
  fall back to composite `(account_holder_id, legal_entity_id, scope, requirement_type)`.

  ## Attributes

  * `id` - UUID primary key
  * `scope` - FATF scope (`account_holder` | `counterparty` | `payment_account` | `beneficial_owner`)
  * `requirement_type` - What document/action is required
  * `status` - Verification state (`pending` | `submitted` | `under_review` | `approved` | `rejected` | `expired`)
  * `deadline` - Optional compliance deadline
  * `kyc_requirement_number` - Opaque external SoE ID (nullable)
  * `account_holder_id` - FK to AccountHolder (MDM subject)
  * `legal_entity_id` - FK to LegalEntity (identity being verified)
  * `document_id` - Optional reference to submitted document
  * `tenant_id` - FK to tenant for multi-tenancy isolation (RLS)
  * `inserted_at` - Timestamp when record was created
  * `updated_at` - Timestamp when record was last updated
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [
      :id,
      :tenant_id,
      :scope,
      :requirement_type,
      :status,
      :account_holder_id,
      :legal_entity_id
    ],
    sortable: [:id, :inserted_at, :updated_at, :scope, :requirement_type, :status, :deadline],
    default_limit: 20,
    max_limit: 100
  }

  # OpenAPI annotations
  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{
      type: :string,
      enum: ["account_holder", "counterparty", "payment_account", "beneficial_owner"]
    },
    key: :scope
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      enum: [
        "identity_document",
        "proof_of_address",
        "source_of_funds",
        "business_relationship",
        "pep_declaration",
        "ubo_declaration",
        "purpose_of_payment"
      ]
    },
    key: :requirement_type
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: ["pending", "submitted", "under_review", "approved", "rejected", "expired"]
    },
    key: :status
  )

  open_api_property(
    schema: %Schema{type: :string, format: :date, nullable: true},
    key: :deadline
  )

  open_api_property(
    schema: %Schema{type: :string, nullable: true},
    key: :kyc_requirement_number
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid},
    key: :account_holder_id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid},
    key: :legal_entity_id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, nullable: true},
    key: :document_id
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
    title: "KycRequirement",
    description:
      "KYC verification requirement — one row per compliance check at a given FATF scope. " <>
        "`account_holder_id` is always the MDM subject; `legal_entity_id` is the identity being verified. " <>
        "Natural key: (account_holder_id, legal_entity_id, scope, requirement_type).",
    required: [:scope, :requirement_type, :account_holder_id, :legal_entity_id, :tenant_id],
    properties: [
      :id,
      :scope,
      :requirement_type,
      :status,
      :deadline,
      :kyc_requirement_number,
      :account_holder_id,
      :legal_entity_id,
      :document_id,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "kyc_requirements" do
    field :scope, Ecto.Enum,
      values: [:account_holder, :counterparty, :payment_account, :beneficial_owner]

    field :requirement_type, Ecto.Enum,
      values: [
        :identity_document,
        :proof_of_address,
        :source_of_funds,
        :business_relationship,
        :pep_declaration,
        :ubo_declaration,
        :purpose_of_payment
      ]

    field :status, Ecto.Enum,
      values: [:pending, :submitted, :under_review, :approved, :rejected, :expired],
      default: :pending

    field :deadline, :date

    field :kyc_requirement_number, :string

    belongs_to :account_holder, AccountHolder
    belongs_to :legal_entity, LegalEntity

    # Optional document reference (no FK — doc may not yet exist)
    field :document_id, :binary_id

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(kyc_requirement, attrs) do
    kyc_requirement
    |> cast(attrs, [
      :scope,
      :requirement_type,
      :deadline,
      :kyc_requirement_number,
      :account_holder_id,
      :legal_entity_id,
      :document_id,
      :tenant_id
    ])
    |> maybe_cast_status(attrs)
    |> validate_required([
      :scope,
      :requirement_type,
      :account_holder_id,
      :legal_entity_id,
      :tenant_id
    ])
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:legal_entity_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint(:kyc_requirement_number,
      name: :kyc_requirements_number_unique,
      message: "has already been taken"
    )
    |> unique_constraint([:account_holder_id, :legal_entity_id, :scope, :requirement_type],
      name: :kyc_requirements_identity_unique,
      message: "requirement already exists for this account holder, legal entity, scope and type"
    )
  end

  # Only cast status when explicitly provided and non-nil.
  # ExOpenApiUtils.Changeset.cast/3 calls Mapper.to_map internally, which includes all struct
  # fields even when nil. Casting nil status would override the Ecto/DB default of :pending.
  defp maybe_cast_status(changeset, attrs) do
    status = Map.get(attrs, :status)

    if is_nil(status) do
      changeset
    else
      # Use raw Ecto.Changeset.cast to properly coerce through Ecto.Enum
      Ecto.Changeset.cast(changeset, %{status: status}, [:status])
    end
  end
end
