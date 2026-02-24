defmodule PaymentCompliancePlatform.CounterpartyContext.Counterparty do
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.AccountHolderContext.AccountHolder
  alias PaymentCompliancePlatform.LegalEntityContext.LegalEntity
  alias PaymentCompliancePlatform.TenantContext.Tenant

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
    schema: %Schema{type: :string, format: :uuid},
    key: :legal_entity_id
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
        "All PII lives in the linked LegalEntity.",
    required: [:account_holder_id, :legal_entity_id, :status],
    properties: [
      :id,
      :account_holder_id,
      :legal_entity_id,
      :status,
      :counterparty_number,
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

    # Virtual: controls whether a compliance screening job is enqueued on create
    field :chain_screening, :boolean, virtual: true, default: true

    belongs_to :tenant, Tenant

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
      :tenant_id
    ])
    |> validate_required([:account_holder_id, :legal_entity_id, :status, :tenant_id])
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:legal_entity_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:account_holder_id, :legal_entity_id],
      name: :counterparties_account_holder_legal_entity_unique
    )
  end
end
