defmodule PaymentCompliancePlatform.AccountHolderContext.AccountHolder.InterestedIndividual do
  @moduledoc """
  Embedded schema for interested individual data in account holder onboarding.

  Reuses Watchman Address and Contact schemas for consistency.
  """
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.Watchman.{Address, Contact}

  @primary_key false
  typed_embedded_schema do
    open_api_property(schema: %Schema{type: :string}, key: :first_name)
    field :first_name, :string

    open_api_property(schema: %Schema{type: :string}, key: :last_name)
    field :last_name, :string

    open_api_property(schema: %Schema{type: :string}, key: :gender)
    field :gender, :string

    open_api_property(schema: %Schema{type: :string}, key: :birth_date)
    field :birth_date, :string

    open_api_property(schema: %Schema{type: :string}, key: :death_date)
    field :death_date, :string

    open_api_property(schema: %Schema{type: :array, items: %Schema{type: :string}}, key: :titles)
    field :titles, {:array, :string}, default: []

    embeds_many :addresses, Address, on_replace: :delete
    embeds_one :contact, Contact, on_replace: :update

    open_api_schema(
      title: "InterestedIndividual",
      description: "Interested individual for account holder screening",
      required: [:first_name, :last_name],
      properties: [
        :first_name,
        :last_name,
        :gender,
        :birth_date,
        :death_date,
        :titles,
        :addresses,
        :contact
      ]
    )
  end

  @doc false
  def changeset(individual, attrs) do
    individual
    |> cast(attrs, [:first_name, :last_name, :gender, :birth_date, :death_date, :titles])
    |> validate_required([:first_name, :last_name])
    |> cast_embed(:addresses)
    |> cast_embed(:contact)
  end
end
