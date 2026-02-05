defmodule PaymentCompliancePlatform.BlocklistContext.BlocklistEntry do
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.TenantContext.Tenant
  alias PaymentCompliancePlatform.UserContext.User

  @derive {
    Flop.Schema,
    filterable: [:id, :tenant_id, :scope, :entry_type, :active],
    sortable: [:id, :inserted_at, :updated_at, :scope, :entry_type],
    default_limit: 20,
    max_limit: 100
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  # OpenAPI annotations
  open_api_property(
    schema: %Schema{type: :string, enum: ["first_name", "last_name", "company_name"]},
    key: :scope
  )

  open_api_property(
    schema: %Schema{type: :string, enum: ["exact", "regex"]},
    key: :entry_type
  )

  open_api_property(schema: %Schema{type: :string}, key: :term)
  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :reason)
  open_api_property(schema: %Schema{type: :boolean, default: true}, key: :active)

  open_api_schema(
    title: "BlocklistEntry",
    description: "Blocklist entry for account holder screening with tenant isolation",
    required: [:scope, :entry_type, :term, :tenant_id],
    properties: [
      :id,
      :scope,
      :entry_type,
      :term,
      :reason,
      :active,
      :added_by_id,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "blocklist_entries" do
    field :scope, Ecto.Enum, values: [:first_name, :last_name, :company_name]
    field :entry_type, Ecto.Enum, values: [:exact, :regex]
    field :term, :string
    field :reason, :string
    field :active, :boolean, default: true

    belongs_to :added_by, User
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(blocklist_entry, attrs) do
    blocklist_entry
    |> cast(attrs, [:scope, :entry_type, :term, :reason, :active, :added_by_id, :tenant_id])
    |> validate_required([:scope, :entry_type, :term, :tenant_id])
    |> validate_regex_compilation()
  end

  defp validate_regex_compilation(changeset) do
    entry_type = get_field(changeset, :entry_type)
    term = get_field(changeset, :term)

    if entry_type == :regex && term do
      case Regex.compile(term) do
        {:ok, _} -> changeset
        {:error, reason} -> add_error(changeset, :term, "invalid regex: #{inspect(reason)}")
      end
    else
      changeset
    end
  end
end
