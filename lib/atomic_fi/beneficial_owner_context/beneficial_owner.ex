defmodule AtomicFi.BeneficialOwnerContext.BeneficialOwner do
  use AtomicFi.Schema

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.LegalEntityContext.LegalEntity
  alias AtomicFi.TenantContext.Tenant

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
    schema: %Schema{type: :string, format: :uuid, nullable: true},
    key: :legal_entity_id
  )

  open_api_property(
    schema: %OpenApiSpex.Reference{"$ref": "#/components/schemas/LegalEntityRequest"},
    key: :legal_entity,
    writeOnly: true
  )

  open_api_property(
    schema: %OpenApiSpex.Reference{"$ref": "#/components/schemas/LegalEntityResponse"},
    key: :legal_entity,
    readOnly: true
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

  open_api_property(
    schema: %Schema{
      type: :boolean,
      writeOnly: true,
      default: true,
      description:
        "When true (default), enqueues a compliance screening job after creation. Set to false to skip."
    },
    key: :chain_screening
  )

  open_api_schema(
    title: "BeneficialOwner",
    description:
      "Beneficial owner of a corporate account holder. " <>
        "≥25% ownership triggers FinCEN CDD Rule 31 CFR §1010.230 (FATF Rec 24). " <>
        "All PII lives in the linked LegalEntity.",
    required: [:account_holder_id, :control_type],
    properties: [
      :id,
      :account_holder_id,
      :legal_entity_id,
      :legal_entity,
      :ownership_pct,
      :control_type,
      :verification_status,
      :beneficial_owner_number,
      :tenant_id,
      :inserted_at,
      :updated_at,
      :chain_screening
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

    # Virtual: controls whether a compliance screening job is enqueued on create
    field :chain_screening, :boolean, virtual: true, default: true

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    # FK to the currently-scheduled OnboardingWorker job. Owned by
    # OnboardingContext / OnboardingWorker — see their moduledocs.
    belongs_to :rescreen_job, Oban.Job, type: :integer

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
    |> maybe_cast_assoc_legal_entity(attrs)
    |> validate_required([:account_holder_id, :control_type, :tenant_id])
    |> validate_legal_entity_present()
    |> validate_number(:ownership_pct, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> AtomicFi.Identifier.put_default(:beneficial_owner_number, :bo)
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:legal_entity_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:account_holder_id, :legal_entity_id],
      name: :beneficial_owners_account_holder_legal_entity_unique
    )
  end

  # Cast nested legal_entity only when present in attrs.
  defp maybe_cast_assoc_legal_entity(changeset, attrs) do
    case Map.fetch(attrs, :legal_entity) do
      {:ok, value} when not is_nil(value) ->
        cast_assoc(changeset, :legal_entity, required: true)

      _ ->
        changeset
    end
  end

  # Require either legal_entity_id (FK) or a nested legal_entity in this changeset.
  defp validate_legal_entity_present(changeset) do
    legal_entity_id = get_field(changeset, :legal_entity_id)
    has_nested = Map.has_key?(changeset.changes, :legal_entity)

    if is_nil(legal_entity_id) and not has_nested do
      add_error(
        changeset,
        :legal_entity_id,
        "must provide either legal_entity_id or a nested legal_entity"
      )
    else
      changeset
    end
  end
end
