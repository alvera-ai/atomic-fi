defmodule PaymentCompliancePlatform.DecisionContext.Decision.BlocklistMatch do
  @moduledoc """
  Represents a blocklist match for entity screening.

  Includes blocklist_updated_at timestamp for human override workflow.
  """
  use PaymentCompliancePlatform.Schema

  @primary_key false
  typed_embedded_schema do
    open_api_property(schema: %Schema{type: :string}, key: :matched_term)
    field :matched_term, :string

    open_api_property(
      schema: %Schema{type: :string, enum: ["exact", "regex"]},
      key: :match_type
    )

    field :match_type, Ecto.Enum, values: [:exact, :regex]

    open_api_property(
      schema: %Schema{type: :string, enum: ["first_name", "last_name", "company_name"]},
      key: :scope
    )

    field :scope, Ecto.Enum, values: [:first_name, :last_name, :company_name]

    open_api_property(schema: %Schema{type: :string, nullable: true}, key: :reason)
    field :reason, :string

    open_api_property(
      schema: %Schema{type: :string, format: :"date-time"},
      key: :blocklist_updated_at
    )

    field :blocklist_updated_at, :utc_datetime_usec

    # Manual review fields
    open_api_property(schema: %Schema{type: :boolean}, key: :false_positive)
    field :false_positive, :boolean, default: false

    open_api_property(schema: %Schema{type: :string, nullable: true}, key: :comment)
    field :comment, :string

    open_api_property(
      schema: %Schema{type: :string, format: :uuid, nullable: true},
      key: :reviewed_by_user_id
    )

    field :reviewed_by_user_id, Ecto.UUID

    open_api_property(
      schema: %Schema{type: :string, format: :"date-time", nullable: true},
      key: :reviewed_at
    )

    field :reviewed_at, :utc_datetime_usec

    open_api_schema(
      title: "BlocklistMatch",
      description: "Blocklist match with timestamp for human override workflow",
      required: [:matched_term, :match_type, :scope, :blocklist_updated_at],
      properties: [
        :matched_term,
        :match_type,
        :scope,
        :reason,
        :blocklist_updated_at,
        :false_positive,
        :comment,
        :reviewed_by_user_id,
        :reviewed_at
      ]
    )
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
      :false_positive,
      :comment,
      :reviewed_by_user_id,
      :reviewed_at
    ])
    |> validate_required([:matched_term, :match_type, :scope, :blocklist_updated_at])
  end
end
