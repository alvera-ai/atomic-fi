defmodule PaymentCompliancePlatform.Watchman.Address do
  @moduledoc """
  Embedded schema for address data (Watchman API format).
  """
  use PaymentCompliancePlatform.Schema

  @primary_key false
  typed_embedded_schema do
    open_api_property(schema: %Schema{type: :string}, key: :city)
    field :city, :string

    open_api_property(schema: %Schema{type: :string}, key: :country)
    field :country, :string

    open_api_property(schema: %Schema{type: :string}, key: :line1)
    field :line1, :string

    open_api_property(schema: %Schema{type: :string}, key: :line2)
    field :line2, :string

    open_api_property(schema: %Schema{type: :string}, key: :postalCode)
    field :postalCode, :string

    open_api_property(schema: %Schema{type: :string}, key: :state)
    field :state, :string

    open_api_schema(
      title: "Address",
      description: "Address information (Watchman format)",
      properties: [:city, :country, :line1, :line2, :postalCode, :state]
    )
  end

  @doc false
  def changeset(address, attrs) do
    address
    |> cast(attrs, [:city, :country, :line1, :line2, :postalCode, :state])
  end

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(type \\ :t)

  def __fields__(:t) do
    [
      city: :string,
      country: :string,
      line1: :string,
      line2: :string,
      postalCode: :string,
      state: :string
    ]
  end
end
