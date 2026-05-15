defmodule AtomicFi.CounterpartyContext.Counterparty do
  use AtomicFi.Schema

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.LegalEntityContext.LegalEntity
  alias AtomicFi.TenantContext.Tenant

  @typedoc """
  Counterparty — the external payer/payee that an AccountHolder transacts with.

  Implements ISO 20022 <Dbtr>/<Cdtr> identity. All PII lives in the linked
  LegalEntity. Each (account_holder_id, legal_entity_id) pair is unique —
  one counterparty record per external party per internal account holder.

  ## Attributes

  * `id` - UUID primary key
  * `account_holder_id` - FK to the internal AccountHolder transacting with this party
  * `legal_entity_id` - FK to LegalEntity (all PII / identity for the external party)
  * `status` - Relationship lifecycle: `active` | `suspended` | `blocked`
  * `counterparty_number` - Opaque external SoE identifier (nullable)
  * `tenant_id` - FK to tenant for multi-tenancy isolation (RLS)
  * `inserted_at` - Timestamp when record was created
  * `updated_at` - Timestamp when record was last updated
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [:id, :tenant_id, :account_holder_id, :status],
    sortable: [:id, :inserted_at, :updated_at, :status],
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
    schema: %Schema{
      type: :string,
      enum: ["active", "suspended", "blocked"]
    },
    key: :status
  )

  open_api_property(
    schema: %Schema{type: :string, nullable: true},
    key: :counterparty_number
  )

  open_api_property(
    schema: %Schema{type: :array, nullable: true, items: %Schema{type: :string}},
    key: :enabled_regimes
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
    title: "Counterparty",
    description:
      "External payer/payee (ISO 20022 <Dbtr>/<Cdtr>) that an AccountHolder transacts with. " <>
        "All PII lives in the linked LegalEntity. " <>
        "Pass either `legal_entity_id` (FK to an existing LegalEntity) or a nested `legal_entity` object to create one atomically.",
    required: [:account_holder_id, :status],
    properties: [
      :id,
      :account_holder_id,
      :legal_entity_id,
      :legal_entity,
      :status,
      :counterparty_number,
      :enabled_regimes,
      :tenant_id,
      :inserted_at,
      :updated_at,
      :chain_screening
    ]
  )

  typed_schema "counterparties" do
    belongs_to :account_holder, AccountHolder
    belongs_to :legal_entity, LegalEntity

    field :status, Ecto.Enum, values: [:active, :suspended, :blocked], default: :active

    field :counterparty_number, :string
    field :enabled_regimes, {:array, :string}, default: []

    # Virtual: controls whether a compliance screening job is enqueued on create
    field :chain_screening, :boolean, virtual: true, default: true

    belongs_to :tenant, Tenant

    # FK to the currently-scheduled OnboardingWorker job. Owned by
    # OnboardingContext / OnboardingWorker — see their moduledocs.
    belongs_to :rescreen_job, Oban.Job, type: :integer

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(counterparty, attrs) do
    counterparty
    |> cast(attrs, [
      :account_holder_id,
      :legal_entity_id,
      :status,
      :counterparty_number,
      :enabled_regimes,
      :tenant_id
    ])
    |> maybe_cast_assoc_legal_entity(attrs)
    |> validate_required([:account_holder_id, :status, :tenant_id])
    |> validate_legal_entity_present()
    |> cast_and_validate_enabled_regimes()
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:legal_entity_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:account_holder_id, :legal_entity_id],
      name: :counterparties_account_holder_legal_entity_unique
    )
  end

  # Parent is the linked AccountHolder. Repo lookup deferred via prepare_changes/2.
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
    case Ecto.Changeset.get_field(prepared, :account_holder_id) do
      nil -> AtomicFi.EnabledRegimes.default()
      account_holder_id -> account_holder_regimes(prepared.repo, account_holder_id)
    end
  end

  defp account_holder_regimes(repo, account_holder_id) do
    case repo.get(AccountHolder, account_holder_id, skip_multi_tenancy_check: true) do
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

  # Require either legal_entity_id (FK to existing) or a nested legal_entity change.
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
