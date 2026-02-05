defmodule PaymentCompliancePlatform.DecisionContext.Decision.EntityDecision do
  @moduledoc """
  Represents screening result for one entity (individual or company).

  Contains entity-level screening summary plus all Watchman sanctions matches.
  Manual review can happen at both entity level and per-match level.
  """
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.DecisionContext.Decision.SanctionsMatch

  @primary_key false
  typed_embedded_schema do
    # Entity being screened (from request)
    open_api_property(
      schema: %Schema{type: :string, enum: ["interested_individual", "interested_company"]},
      key: :entity_type
    )

    field :entity_type, Ecto.Enum, values: [:interested_individual, :interested_company]

    open_api_property(schema: %Schema{type: :string}, key: :entity_name)
    field :entity_name, :string

    # Watchman screening result
    open_api_property(
      schema: %Schema{type: :string, enum: ["pass", "potential_match", "blocked"]},
      key: :screening_result
    )

    field :screening_result, Ecto.Enum, values: [:pass, :potential_match, :blocked]

    open_api_property(schema: %Schema{type: :integer}, key: :match_count)
    field :match_count, :integer, default: 0

    open_api_property(schema: %Schema{type: :number, format: :float}, key: :highest_match_score)
    field :highest_match_score, :float

    open_api_property(schema: %Schema{type: :string, format: :"date-time"}, key: :screened_at)
    field :screened_at, :utc_datetime_usec

    # All Watchman matches for this entity
    open_api_property(
      schema: %Schema{
        type: :array,
        items: %OpenApiSpex.Reference{"$ref": "#/components/schemas/SanctionsMatchResponse"}
      },
      key: :sanctions_matches
    )

    embeds_many :sanctions_matches, SanctionsMatch, on_replace: :delete

    # Entity-level manual review
    open_api_property(schema: %Schema{type: :boolean}, key: :false_positive)
    field :false_positive, :boolean, default: false

    open_api_property(schema: %Schema{type: :string}, key: :comment)
    field :comment, :string

    open_api_property(schema: %Schema{type: :string, format: :uuid}, key: :reviewed_by_user_id)
    field :reviewed_by_user_id, Ecto.UUID

    open_api_property(schema: %Schema{type: :string, format: :"date-time"}, key: :reviewed_at)
    field :reviewed_at, :utc_datetime_usec

    open_api_schema(
      title: "EntityDecision",
      description:
        "Screening result for one entity (individual or company) with sanctions matches",
      required: [:entity_type, :entity_name, :screening_result, :screened_at],
      properties: [
        :entity_type,
        :entity_name,
        :screening_result,
        :match_count,
        :highest_match_score,
        :screened_at,
        :sanctions_matches,
        :false_positive,
        :comment,
        :reviewed_by_user_id,
        :reviewed_at
      ]
    )
  end

  @doc false
  def changeset(entity_decision, attrs) do
    entity_decision
    |> cast(attrs, [
      :entity_type,
      :entity_name,
      :screening_result,
      :match_count,
      :highest_match_score,
      :screened_at,
      :false_positive,
      :comment,
      :reviewed_by_user_id,
      :reviewed_at
    ])
    |> validate_required([:entity_type, :entity_name, :screening_result, :screened_at])
    |> cast_embed(:sanctions_matches)
  end
end
