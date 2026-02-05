defmodule PaymentCompliancePlatform.DecisionContext.Decision.SanctionsMatch do
  @moduledoc """
  Represents one Watchman sanctions list match for a screened entity.

  Each SanctionsMatch contains the raw match data from Watchman API
  plus manual review fields for compliance team to mark false positives.
  """
  use PaymentCompliancePlatform.Schema

  @primary_key false
  typed_embedded_schema do
    # Watchman Entity match data (first-class fields)
    open_api_property(schema: %Schema{type: :string}, key: :matched_name)
    field :matched_name, :string

    open_api_property(schema: %Schema{type: :string}, key: :matched_entity_type)
    field :matched_entity_type, :string

    open_api_property(schema: %Schema{type: :number, format: :float}, key: :match_score)
    field :match_score, :float

    open_api_property(schema: %Schema{type: :string}, key: :source_list)
    field :source_list, :string

    open_api_property(schema: %Schema{type: :string}, key: :source_id)
    field :source_id, :string

    # Complex Watchman data as maps
    open_api_property(
      schema: %Schema{type: :array, items: %Schema{type: :object}},
      key: :addresses
    )

    field :addresses, {:array, :map}, default: []

    open_api_property(schema: %Schema{type: :object}, key: :business_data)
    field :business_data, :map

    open_api_property(schema: %Schema{type: :object}, key: :person_data)
    field :person_data, :map

    open_api_property(schema: %Schema{type: :object}, key: :contact_data)
    field :contact_data, :map

    open_api_property(schema: %Schema{type: :object}, key: :source_data)
    field :source_data, :map

    # Manual review fields
    open_api_property(schema: %Schema{type: :boolean}, key: :false_positive)
    field :false_positive, :boolean, default: false

    open_api_property(schema: %Schema{type: :string}, key: :comment)
    field :comment, :string

    open_api_property(schema: %Schema{type: :string, format: :uuid}, key: :reviewed_by_user_id)
    field :reviewed_by_user_id, Ecto.UUID

    open_api_property(schema: %Schema{type: :string, format: :"date-time"}, key: :reviewed_at)
    field :reviewed_at, :utc_datetime_usec

    open_api_schema(
      title: "SanctionsMatch",
      description: "One Watchman sanctions match with manual review capability",
      required: [:matched_name, :match_score, :source_list],
      properties: [
        :matched_name,
        :matched_entity_type,
        :match_score,
        :source_list,
        :source_id,
        :addresses,
        :business_data,
        :person_data,
        :contact_data,
        :source_data,
        :false_positive,
        :comment,
        :reviewed_by_user_id,
        :reviewed_at
      ]
    )
  end

  @doc false
  def changeset(sanctions_match, attrs) do
    sanctions_match
    |> cast(attrs, [
      :matched_name,
      :matched_entity_type,
      :match_score,
      :source_list,
      :source_id,
      :addresses,
      :business_data,
      :person_data,
      :contact_data,
      :source_data,
      :false_positive,
      :comment,
      :reviewed_by_user_id,
      :reviewed_at
    ])
    |> validate_required([:matched_name, :match_score, :source_list])
  end
end
