defmodule AtomicFi.AccountHolderContext.AccountHolder do
  use AtomicFi.Schema

  alias AtomicFi.LegalEntityContext.LegalEntity
  alias AtomicFi.TenantContext.Tenant

  @typedoc """
  Account holder — the MDM subject that controls an account (ISO 20022 acmt:007, acmt:019).

  Operational state lives here. All PII lives in the linked LegalEntity.

  ## Attributes

  * `id` - UUID primary key
  * `legal_entity_id` - FK to LegalEntity (all PII / identity)
  * `external_id` - Upstream ID (Stripe/JPMC/Moov), unique per tenant
  * `holder_type` - `individual` | `business` | `trust` | `nonprofit`
  * `status` - `pending` | `active` | `suspended` | `closed`
  * `kyc_status` - `not_started` | `in_progress` | `approved` | `rejected` | `expired`
  * `risk_level` - `low` | `medium` | `high` | `very_high` | `prohibited`
  * `enabled_currencies` - ISO 4217 codes (each creates a Ledger)
  * `account_holder_number` - Opaque internal identifier
  * `onboarded_at` - Timestamp when account holder was onboarded
  * `last_reviewed_at` - Timestamp when account holder was last reviewed
  * `tenant_id` - FK to tenant for multi-tenancy isolation (RLS)
  * `inserted_at` - Timestamp when record was created
  * `updated_at` - Timestamp when record was last updated
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [:id, :tenant_id, :holder_type, :status, :kyc_status, :risk_level],
    sortable: [:id, :inserted_at, :updated_at, :holder_type, :status, :onboarded_at],
    default_limit: 20,
    max_limit: 100
  }

  # OpenAPI annotations
  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

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

  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :external_id)

  open_api_property(
    schema: %Schema{type: :string, enum: ["individual", "business", "trust", "nonprofit"]},
    key: :holder_type
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: ["pending", "active", "suspended", "closed", "flagged"]
    },
    key: :status
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: ["not_started", "in_progress", "approved", "rejected", "expired"]
    },
    key: :kyc_status
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: ["low", "medium", "high", "very_high"]
    },
    key: :risk_level
  )

  open_api_property(
    schema: %Schema{type: :array, nullable: true, items: %Schema{type: :string}},
    key: :enabled_currencies
  )

  open_api_property(
    schema: %Schema{type: :array, nullable: true, items: %Schema{type: :string}},
    key: :enabled_regimes
  )

  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :account_holder_number)

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", nullable: true},
    key: :onboarded_at
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", nullable: true},
    key: :last_reviewed_at
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
    title: "AccountHolder",
    description:
      "Account holder — the MDM subject controlling an account. " <>
        "All PII lives in the linked LegalEntity (ISO 20022 acmt:007 / acmt:019). " <>
        "Pass either `legal_entity_id` (FK to an existing LegalEntity) or a nested `legal_entity` object to create one atomically.",
    required: [:holder_type],
    properties: [
      :id,
      :legal_entity_id,
      :legal_entity,
      :external_id,
      :holder_type,
      :status,
      :kyc_status,
      :risk_level,
      :enabled_currencies,
      :enabled_regimes,
      :account_holder_number,
      :onboarded_at,
      :last_reviewed_at,
      :tenant_id,
      :inserted_at,
      :updated_at,
      :chain_screening
    ]
  )

  typed_schema "account_holders" do
    belongs_to :legal_entity, LegalEntity

    field :external_id, :string

    field :holder_type, Ecto.Enum, values: [:individual, :business, :trust, :nonprofit]

    field :status, Ecto.Enum,
      values: [:pending, :active, :suspended, :closed, :flagged],
      default: :pending

    field :kyc_status, Ecto.Enum,
      values: [:not_started, :in_progress, :approved, :rejected, :expired],
      default: :not_started

    field :risk_level, Ecto.Enum,
      values: [:low, :medium, :high, :very_high],
      default: :low

    field :enabled_currencies, {:array, :string}, default: []
    field :enabled_regimes, {:array, :string}, default: []

    field :account_holder_number, :string

    field :onboarded_at, :utc_datetime_usec
    field :last_reviewed_at, :utc_datetime_usec

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
  def changeset(account_holder, attrs) do
    account_holder
    |> cast(attrs, [
      :legal_entity_id,
      :external_id,
      :holder_type,
      :status,
      :kyc_status,
      :risk_level,
      :enabled_currencies,
      :enabled_regimes,
      :account_holder_number,
      :onboarded_at,
      :last_reviewed_at,
      :tenant_id
    ])
    |> maybe_cast_assoc_legal_entity(attrs)
    |> validate_required([:holder_type, :tenant_id])
    |> validate_legal_entity_present()
    |> cast_and_validate_enabled_regimes()
    |> foreign_key_constraint(:legal_entity_id)
    |> foreign_key_constraint(:tenant_id)
  end

  # Parent is the linked Tenant. Repo lookup is deferred via prepare_changes/2,
  # so it fires inside the insert/update txn (not when callers build the
  # changeset for validation preview).
  defp cast_and_validate_enabled_regimes(changeset) do
    Ecto.Changeset.prepare_changes(changeset, fn prepared ->
      AtomicFi.EnabledRegimes.cast_and_validate(
        prepared,
        Ecto.Changeset.get_field(prepared, :enabled_regimes),
        parent_regimes(prepared)
      )
    end)
  end

  defp parent_regimes(prepared) do
    case Ecto.Changeset.get_field(prepared, :tenant_id) do
      nil -> AtomicFi.EnabledRegimes.default()
      tenant_id -> tenant_regimes(prepared.repo, tenant_id)
    end
  end

  defp tenant_regimes(repo, tenant_id) do
    case repo.get(Tenant, tenant_id, skip_multi_tenancy_check: true) do
      nil -> AtomicFi.EnabledRegimes.default()
      %{enabled_regimes: regimes} -> regimes
    end
  end

  # Cast nested legal_entity only when the key is present in attrs (not a nil default).
  defp maybe_cast_assoc_legal_entity(changeset, attrs) do
    case Map.fetch(attrs, :legal_entity) do
      {:ok, value} when not is_nil(value) ->
        cast_assoc(changeset, :legal_entity, required: true)

      _ ->
        changeset
    end
  end

  # Require either legal_entity_id (FK) or a nested legal_entity change in this changeset.
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
