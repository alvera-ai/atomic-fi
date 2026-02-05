defmodule PaymentCompliancePlatform.Watchman.Contact do
  @moduledoc """
  Embedded schema for contact data (Watchman API format).
  """
  use PaymentCompliancePlatform.Schema

  @primary_key false
  typed_embedded_schema do
    open_api_property(
      schema: %Schema{type: :array, items: %Schema{type: :string}},
      key: :emailAddresses
    )

    field :emailAddresses, {:array, :string}, default: []

    open_api_property(
      schema: %Schema{type: :array, items: %Schema{type: :string}},
      key: :faxNumbers
    )

    field :faxNumbers, {:array, :string}, default: []

    open_api_property(
      schema: %Schema{type: :array, items: %Schema{type: :string}},
      key: :phoneNumbers
    )

    field :phoneNumbers, {:array, :string}, default: []

    open_api_property(
      schema: %Schema{type: :array, items: %Schema{type: :string}},
      key: :websites
    )

    field :websites, {:array, :string}, default: []

    open_api_schema(
      title: "Contact",
      description: "Contact information (Watchman format)",
      properties: [:emailAddresses, :faxNumbers, :phoneNumbers, :websites]
    )
  end

  @doc false
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [:emailAddresses, :faxNumbers, :phoneNumbers, :websites])
  end

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(type \\ :t)

  def __fields__(:t) do
    [
      emailAddresses: [:string],
      faxNumbers: [:string],
      phoneNumbers: [:string],
      websites: [:string]
    ]
  end
end
