defmodule PaymentCompliancePlatform.AccountHolderContext.AccountHolder do
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.AccountHolderContext.AccountHolder.{
    InterestedCompany,
    InterestedIndividual,
    RawBody
  }

  alias PaymentCompliancePlatform.TenantContext.Tenant

  @derive {
    Flop.Schema,
    filterable: [:id, :tenant_id, :name, :type],
    sortable: [:id, :inserted_at, :updated_at, :name, :type],
    default_limit: 20,
    max_limit: 100
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # OpenAPI annotations
  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)
  open_api_property(schema: %Schema{type: :string}, key: :name)
  open_api_property(schema: %Schema{type: :string, enum: ["individual", "business"]}, key: :type)

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, readOnly: true},
    key: :tenant_id
  )

  open_api_property(
    schema: %Schema{
      type: :array,
      items: %OpenApiSpex.Reference{"$ref": "#/components/schemas/InterestedCompanyRequest"}
    },
    key: :interested_companies
  )

  open_api_property(
    schema: %Schema{
      type: :array,
      items: %OpenApiSpex.Reference{"$ref": "#/components/schemas/InterestedIndividualRequest"}
    },
    key: :interested_individuals
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
    title: "AccountHolder",
    description: "Account holder schema",
    required: [:name, :type],
    properties: [
      :id,
      :name,
      :type,
      :tenant_id,
      :interested_companies,
      :interested_individuals,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "account_holders" do
    field :name, :string
    field :type, Ecto.Enum, values: [:individual, :business]

    embeds_many :interested_companies, InterestedCompany, on_replace: :delete
    embeds_many :interested_individuals, InterestedIndividual, on_replace: :delete
    embeds_one :raw_body, RawBody, on_replace: :update

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(account_holder, attrs) do
    account_holder
    |> cast(attrs, [:name, :type, :tenant_id])
    |> validate_required([:name, :type, :tenant_id])
    |> cast_embed(:interested_companies)
    |> cast_embed(:interested_individuals)
    |> cast_embed(:raw_body)
  end
end
