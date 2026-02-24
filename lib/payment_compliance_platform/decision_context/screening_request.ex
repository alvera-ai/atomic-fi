defmodule PaymentCompliancePlatform.DecisionContext.ScreeningRequest do
  @moduledoc """
  OpenAPI request schema for the onboarding/screen endpoint.

  Captures the interested parties to screen (individuals and companies).
  Decoupled from the AccountHolder Ecto schema — this schema exists solely
  for request validation in the onboarding screening endpoint.
  """

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ScreeningRequest",
    description: "Request body for the onboarding/screen endpoint",
    type: :object,
    properties: %{
      interested_individuals: %Schema{
        type: :array,
        description: "Individuals to screen against sanctions lists",
        items: %OpenApiSpex.Reference{"$ref": "#/components/schemas/InterestedIndividualRequest"}
      },
      interested_companies: %Schema{
        type: :array,
        description: "Companies to screen against sanctions lists",
        items: %OpenApiSpex.Reference{"$ref": "#/components/schemas/InterestedCompanyRequest"}
      }
    },
    required: []
  })
end
