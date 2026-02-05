defmodule PaymentCompliancePlatform.DecisionContext.Decision do
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.AccountHolderContext.AccountHolder
  alias PaymentCompliancePlatform.DecisionContext.Decision.EntityDecision
  alias PaymentCompliancePlatform.TenantContext.Tenant

  @derive {
    Flop.Schema,
    filterable: [
      :id,
      :tenant_id,
      :account_holder_id,
      :overall_status,
      :total_entities_screened,
      :entities_with_matches
    ],
    sortable: [
      :id,
      :inserted_at,
      :updated_at,
      :overall_status,
      :total_entities_screened,
      :entities_with_matches,
      :list_synced_at
    ],
    default_limit: 20,
    max_limit: 100
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # OpenAPI annotations
  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, readOnly: true},
    key: :account_holder_id
  )

  open_api_property(schema: %Schema{type: :string}, key: :overall_status)
  open_api_property(schema: %Schema{type: :integer}, key: :total_entities_screened)
  open_api_property(schema: %Schema{type: :integer}, key: :entities_with_matches)
  open_api_property(schema: %Schema{type: :string, format: :"date-time"}, key: :list_synced_at)
  open_api_property(schema: %Schema{type: :object}, key: :list_sources)
  open_api_property(schema: %Schema{type: :object}, key: :raw_request)

  open_api_property(
    schema: %Schema{
      type: :array,
      items: %OpenApiSpex.Reference{"$ref": "#/components/schemas/EntityDecisionResponse"}
    },
    key: :entity_decisions
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, readOnly: true},
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
    title: "Decision",
    description: "Screening decision for account holder onboarding",
    required: [:account_holder_id, :overall_status, :tenant_id],
    properties: [
      :id,
      :account_holder_id,
      :overall_status,
      :total_entities_screened,
      :entities_with_matches,
      :list_synced_at,
      :list_sources,
      :raw_request,
      :entity_decisions,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "decisions" do
    field :overall_status, :string
    field :total_entities_screened, :integer
    field :entities_with_matches, :integer
    field :list_synced_at, :utc_datetime_usec
    field :list_sources, :map
    field :raw_request, :map

    embeds_many :entity_decisions, EntityDecision, on_replace: :delete

    # Foreign keys
    belongs_to :account_holder, AccountHolder
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(decision, attrs) do
    decision
    |> cast(attrs, [
      :overall_status,
      :total_entities_screened,
      :entities_with_matches,
      :list_synced_at,
      :list_sources,
      :raw_request,
      :account_holder_id,
      :tenant_id
    ])
    |> validate_required([
      :overall_status,
      :total_entities_screened,
      :entities_with_matches,
      :list_synced_at,
      :account_holder_id,
      :tenant_id
    ])
    |> cast_embed(:entity_decisions)
  end
end
