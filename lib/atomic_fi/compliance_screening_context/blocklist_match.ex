defmodule AtomicFi.ComplianceScreeningContext.BlocklistMatch do
  @moduledoc """
  One internal blocklist hit within a ComplianceScreening.

  Each row represents a match against the tenant's internal blocklist (via
  `BlocklistCache` + `BlocklistValidator`) that fired before Watchman was called.
  Blocklist checks are fail-fast — if any match is found the entity is blocked
  immediately and Watchman is not queried.

  ## False Positive Deduplication

  `false_positive_qualifier` persists reviewer decisions across re-screenings:
  - `:manual_override` — compliance reviewer confirmed: not a real match
  - `:auto_suppressed` — system detected a prior `manual_override` for the same
    `(matched_term, scope)` within this tenant; written automatically on re-screen

  `blocklist_updated_at` records the blocklist's last-refresh timestamp at screening
  time. If the blocklist was updated after a `manual_override` was set, reviewers
  can re-evaluate whether the override still applies.

  ## ISO 20022

  Blocklist screening feeds into `ComplianceScreening.screeningStatus` (auth:018).
  """

  use AtomicFi.Schema

  alias AtomicFi.TenantContext.Tenant

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [
      :id,
      :tenant_id,
      :compliance_screening_id,
      :false_positive_qualifier,
      :scope,
      :match_type
    ],
    sortable: [:id, :inserted_at],
    default_limit: 50,
    max_limit: 200
  }

  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, readOnly: true},
    key: :compliance_screening_id
  )

  open_api_property(schema: %Schema{type: :string}, key: :matched_term)

  open_api_property(
    schema: %Schema{type: :string, enum: ["exact", "regex"]},
    key: :match_type
  )

  open_api_property(
    schema: %Schema{type: :string, enum: ["first_name", "last_name", "company_name"]},
    key: :scope
  )

  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :reason)

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", nullable: true},
    key: :blocklist_updated_at
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      enum: ["none", "manual_override", "auto_suppressed"]
    },
    key: :false_positive_qualifier
  )

  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :review_notes)

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, nullable: true},
    key: :reviewed_by_user_id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", nullable: true},
    key: :reviewed_at
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
    title: "BlocklistMatch",
    description:
      "One internal blocklist hit. false_positive_qualifier persists reviewer decisions across " <>
        "re-screenings. blocklist_updated_at lets reviewers re-evaluate overrides after list updates.",
    required: [:matched_term, :match_type, :scope],
    properties: [
      :id,
      :compliance_screening_id,
      :matched_term,
      :match_type,
      :scope,
      :reason,
      :blocklist_updated_at,
      :false_positive_qualifier,
      :review_notes,
      :reviewed_by_user_id,
      :reviewed_at,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "blocklist_matches" do
    field :matched_term, :string
    field :match_type, Ecto.Enum, values: [:exact, :regex]
    field :scope, Ecto.Enum, values: [:first_name, :last_name, :company_name]
    field :reason, :string
    field :blocklist_updated_at, :utc_datetime_usec

    field :false_positive_qualifier, Ecto.Enum,
      values: [:none, :manual_override, :auto_suppressed],
      default: :none

    field :review_notes, :string
    field :reviewed_by_user_id, :binary_id
    field :reviewed_at, :utc_datetime_usec

    belongs_to :compliance_screening,
               AtomicFi.ComplianceScreeningContext.ComplianceScreening

    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(blocklist_match, attrs) do
    blocklist_match
    |> cast(attrs, [
      :matched_term,
      :match_type,
      :scope,
      :reason,
      :blocklist_updated_at,
      :false_positive_qualifier,
      :review_notes,
      :reviewed_by_user_id,
      :reviewed_at,
      :compliance_screening_id,
      :tenant_id
    ])
    |> validate_required([:matched_term, :match_type, :scope, :tenant_id])
    |> foreign_key_constraint(:compliance_screening_id)
    |> foreign_key_constraint(:tenant_id)
  end
end
