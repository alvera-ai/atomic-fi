defmodule PaymentCompliancePlatform.AccountHolderContext.AccountHolder.RawBody do
  @moduledoc """
  Embedded schema for storing raw request body data and metadata.

  Preserves original API request for audit and debugging purposes.
  """
  use PaymentCompliancePlatform.Schema

  @primary_key false
  typed_embedded_schema do
    open_api_property(schema: %Schema{type: :object}, key: :data)
    field :data, :map, default: %{}

    open_api_property(schema: %Schema{type: :object}, key: :metadata)
    field :metadata, :map, default: %{}

    open_api_schema(
      title: "RawBody",
      description: "Raw request body data and metadata",
      properties: [:data, :metadata]
    )
  end

  @doc false
  def changeset(raw_body, attrs) do
    raw_body
    |> cast(attrs, [:data, :metadata])
  end
end
