defmodule PaymentCompliancePlatform.AccountHolderContext.AccountHolder.InterestedCompany do
  @moduledoc """
  Embedded schema for interested company data in account holder onboarding.

  Reuses Watchman Address and Contact schemas for consistency.
  """
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.Watchman.{Address, Contact}

  @primary_key false
  typed_embedded_schema do
    open_api_property(schema: %Schema{type: :string}, key: :name)
    field :name, :string

    open_api_property(schema: %Schema{type: :string}, key: :created)
    field :created, :string

    open_api_property(schema: %Schema{type: :string}, key: :dissolved)
    field :dissolved, :string

    open_api_property(
      schema: %Schema{
        type: :array,
        items: %OpenApiSpex.Reference{"$ref": "#/components/schemas/AddressRequest"}
      },
      key: :addresses
    )

    embeds_many :addresses, Address, on_replace: :delete

    open_api_property(
      schema: %OpenApiSpex.Reference{"$ref": "#/components/schemas/ContactRequest"},
      key: :contact
    )

    embeds_one :contact, Contact, on_replace: :update

    open_api_schema(
      title: "InterestedCompany",
      description: "Interested company for account holder screening",
      required: [:name],
      properties: [:name, :created, :dissolved, :addresses, :contact]
    )
  end

  @doc false
  def changeset(company, attrs) do
    company
    |> cast(attrs, [:name, :created, :dissolved])
    |> validate_required([:name])
    |> cast_embed(:addresses)
    |> cast_embed(:contact)
  end
end
