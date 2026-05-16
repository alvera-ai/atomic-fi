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
  * `legal_entity` - 1:1 identity record (LE carries the FK back via `legal_entities.counterparty_id`)
  * `status` - Relationship lifecycle: `active` | `suspended` | `blocked`
  * `external_id` - Opaque external SoE identifier (nullable)
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
    key: :external_id
  )

  open_api_property(
    schema: %Schema{type: :string, readOnly: true},
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
        "All PII lives in the linked LegalEntity, created atomically via the nested " <>
        "`legal_entity` object on POST. The LE link is immutable post-create " <>
        "(LE carries the FK back, not CP). To replace LE PII, use " <>
        "`PUT /api/counterparties/:id/legal-entity`.",
    # `legal_entity` is required on POST but optional on PUT (cast_assoc is a
    # no-op on update; the LE link is immutable post-create).
    required: [:account_holder_id, :status],
    properties: [
      :id,
      :account_holder_id,
      :legal_entity,
      :status,
      :external_id,
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

    # 1:1 identity. LE carries the FK back via `legal_entities.counterparty_id`.
    # No `where:` filter — `counterparty_id` is non-null only on CP-owned LEs.
    has_one :legal_entity, LegalEntity, foreign_key: :counterparty_id

    field :status, Ecto.Enum, values: [:active, :suspended, :blocked], default: :active

    field :external_id, :string
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
      :status,
      :external_id,
      :counterparty_number,
      :enabled_regimes,
      :tenant_id
    ])
    |> maybe_cast_assoc_legal_entity(attrs)
    |> validate_required([:account_holder_id, :status, :tenant_id])
    |> cast_and_validate_enabled_regimes()
    |> AtomicFi.Identifier.put_default(:counterparty_number, :cp)
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:tenant_id)
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
    account_holder_id = Ecto.Changeset.get_field(prepared, :account_holder_id)

    %AccountHolder{enabled_regimes: regimes} =
      prepared.repo.get!(AccountHolder, account_holder_id, skip_multi_tenancy_check: true)

    regimes
  end

  # cast_assoc nested legal_entity (required on insert, untouched on update —
  # LE PII replacement goes via PUT /api/counterparties/:id/legal-entity).
  # Captures the cast'd `account_holder_id` so the LE's per-parent changeset
  # can put_change it onto the AH-rollup column.
  defp maybe_cast_assoc_legal_entity(%Ecto.Changeset{data: %{id: nil}} = changeset, attrs) do
    case Map.fetch(attrs, :legal_entity) do
      {:ok, value} when not is_nil(value) ->
        account_holder_id = get_field(changeset, :account_holder_id)

        cast_assoc(changeset, :legal_entity,
          required: true,
          with: fn le, le_attrs ->
            LegalEntity.counterparty_changeset(le, le_attrs, account_holder_id)
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
