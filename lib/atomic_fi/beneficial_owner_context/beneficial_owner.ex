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
  * `legal_entity` - 1:1 identity record (LE carries the FK back via `legal_entities.beneficial_owner_id`)
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
        "All PII lives in the linked LegalEntity, created atomically via the nested " <>
        "`legal_entity` object. The LE link is immutable post-create (LE owns the " <>
        "FK back). To replace LE PII, use `PUT /api/beneficial-owners/:id/legal-entity`.",
    # `legal_entity` is required on POST but optional on PUT (cast_assoc is a
    # no-op on update; the LE link is immutable post-create).
    required: [:account_holder_id, :control_type],
    properties: [
      :id,
      :account_holder_id,
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

    # 1:1 identity. LE carries the FK back via `legal_entities.beneficial_owner_id`.
    has_one :legal_entity, LegalEntity, foreign_key: :beneficial_owner_id

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
      :ownership_pct,
      :control_type,
      :verification_status,
      :beneficial_owner_number,
      :tenant_id
    ])
    |> maybe_cast_assoc_legal_entity(attrs)
    |> validate_required([:account_holder_id, :control_type, :tenant_id])
    |> validate_number(:ownership_pct, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> AtomicFi.Identifier.put_default(:beneficial_owner_number, :bo)
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:tenant_id)
  end

  # cast_assoc nested legal_entity (required on insert; untouched on update —
  # LE PII replacement is the dedicated PUT /api/beneficial-owners/:id/legal-entity
  # route). Captures the cast'd `account_holder_id` for the AH-rollup put_change
  # on the LE's per-parent changeset.
  defp maybe_cast_assoc_legal_entity(%Ecto.Changeset{data: %{id: nil}} = changeset, attrs) do
    case Map.fetch(attrs, :legal_entity) do
      {:ok, value} when not is_nil(value) ->
        account_holder_id = get_field(changeset, :account_holder_id)

        cast_assoc(changeset, :legal_entity,
          required: true,
          with: fn le, le_attrs ->
            LegalEntity.beneficial_owner_changeset(le, le_attrs, account_holder_id)
          end
        )

      _ ->
        add_error(
          changeset,
          :legal_entity,
          "is required on create — provide a nested legal_entity object"
        )
    end
  end

  defp maybe_cast_assoc_legal_entity(%Ecto.Changeset{} = changeset, _attrs), do: changeset
end
