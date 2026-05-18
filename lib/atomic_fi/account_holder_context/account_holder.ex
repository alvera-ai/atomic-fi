defmodule AtomicFi.AccountHolderContext.AccountHolder do
  use AtomicFi.Schema

  alias AtomicFi.LegalEntityContext.LegalEntity
  alias AtomicFi.TenantContext.Tenant

  @typedoc """
  Account holder — the MDM subject that controls an account (ISO 20022 acmt:007, acmt:019).

  Operational state lives here. All PII lives in the linked LegalEntity, which
  is reached via `has_one :legal_entity` (LE carries the FK back: `legal_entities.account_holder_id`).

  ## Attributes

  * `id` - UUID primary key
  * `legal_entity` - one-to-one identity record (LE owns the FK back; no
    `legal_entity_id` column on AccountHolder)
  * `external_id` - Upstream ID (Stripe/JPMC/Moov), unique per tenant
  * `account_holder_type` - `individual` | `business` | `trust` | `nonprofit`
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
    filterable: [:id, :tenant_id, :account_holder_type, :status, :kyc_status, :risk_level],
    sortable: [:id, :inserted_at, :updated_at, :account_holder_type, :status, :onboarded_at],
    default_limit: 20,
    max_limit: 100
  }

  # OpenAPI annotations
  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

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
    key: :account_holder_type
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
      enum: ["low", "medium", "high", "very_high", "prohibited"]
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
        "POST creates the LegalEntity atomically via the nested `legal_entity` " <>
        "object — the LE link is immutable post-create (LE carries the FK, " <>
        "not AH). To replace LE PII content, use `PUT /api/account-holders/:id/legal-entity`.",
    # `legal_entity` is required on POST but optional on PUT (cast_assoc is a
    # no-op on update; the LE link is immutable post-create). Enforcing it at
    # the Ecto layer keeps schema validation consistent across both verbs.
    required: [:account_holder_type],
    properties: [
      :id,
      :legal_entity,
      :external_id,
      :account_holder_type,
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
    # 1:1 identity record. LE carries the FK back via `legal_entities.account_holder_id`
    # (filtered by subject_type=:account_holder so this assoc doesn't include
    # CP-owned or BO-owned LEs that roll up to the same AH for compliance).
    has_one :legal_entity, LegalEntity,
      foreign_key: :account_holder_id,
      where: [subject_type: :account_holder]

    # FinCEN CDD §1010.230 / Corporate Transparency Act beneficial owners
    # of this AccountHolder. Walked through the AH's BO-LE rows: an LE
    # whose `subject_type = :account_holder_beneficial_owner` and whose
    # `account_holder_id = ah.id` points (via `beneficial_owner_id`) at
    # the BO row itself. The `:counterparty_beneficial_owner` variant —
    # BOs of one of this AH's Counterparties — lives on the Counterparty
    # schema (`Counterparty.has_many :beneficial_owners`), so this assoc
    # never bleeds CP-side BOs into AH-side compliance.
    has_many :account_holder_beneficial_owner_legal_entities, LegalEntity,
      foreign_key: :account_holder_id,
      where: [subject_type: :account_holder_beneficial_owner]

    has_many :beneficial_owners,
      through: [:account_holder_beneficial_owner_legal_entities, :beneficial_owner]

    field :external_id, :string

    field :account_holder_type, Ecto.Enum, values: [:individual, :business, :trust, :nonprofit]

    field :status, Ecto.Enum,
      values: [:pending, :active, :suspended, :closed, :flagged],
      default: :pending

    field :kyc_status, Ecto.Enum,
      values: [:not_started, :in_progress, :approved, :rejected, :expired],
      default: :not_started

    field :risk_level, Ecto.Enum,
      values: [:low, :medium, :high, :very_high, :prohibited],
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
      :external_id,
      :account_holder_type,
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
    |> validate_required([:account_holder_type, :tenant_id])
    |> cast_and_validate_enabled_regimes()
    |> AtomicFi.Identifier.put_default(:account_holder_number, :ah)
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
    tenant_id = Ecto.Changeset.get_field(prepared, :tenant_id)

    %Tenant{enabled_regimes: regimes} =
      prepared.repo.get!(Tenant, tenant_id, skip_multi_tenancy_check: true)

    regimes
  end

  # cast_assoc nested legal_entity only when the key is present in attrs (not a
  # nil default). The per-parent `account_holder_changeset/2` on LE puts
  # `subject_type` via put_change — Ecto's has_one foreign_key auto-sets
  # `legal_entity.account_holder_id` from the inserted AH's id.
  #
  # Required on INSERT (every AH must have its identity LE), optional on
  # UPDATE (existing LE stays put — replacing LE PII goes through the
  # nested `PUT /api/account-holders/:id/legal-entity` route).
  defp maybe_cast_assoc_legal_entity(%Ecto.Changeset{data: %{id: nil}} = changeset, attrs) do
    case Map.fetch(attrs, :legal_entity) do
      {:ok, value} when not is_nil(value) ->
        cast_assoc(changeset, :legal_entity,
          required: true,
          with: &LegalEntity.account_holder_changeset/2
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
