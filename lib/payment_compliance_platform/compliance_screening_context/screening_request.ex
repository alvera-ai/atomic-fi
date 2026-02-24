defmodule PaymentCompliancePlatform.ComplianceScreeningContext.ScreeningRequest do
  @moduledoc """
  OpenApiSpex request struct for the compliance screening endpoints.

  Parsed and validated by `OpenApiSpex.Plug.CastAndValidate` before reaching
  the controller. Used by `ComplianceScreeningContext.screen_account_holder/2`,
  `screen_beneficial_owner/2`, and `screen_counterparty/2`.
  """

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ScreeningRequest",
    description:
      "Request body for compliance screening. " <>
        "Screens all listed individuals and companies against the internal blocklist " <>
        "and Watchman OFAC/SDN/EU/UN sanctions lists.",
    type: :object,
    required: [:account_holder_id],
    properties: %{
      account_holder_id: %Schema{
        type: :string,
        format: :uuid,
        description: "ID of the account holder to screen"
      },
      counterparty_id: %Schema{
        type: :string,
        format: :uuid,
        nullable: true,
        description: "ID of the counterparty to screen (required for screen_counterparty)"
      },
      interested_individuals: %Schema{
        type: :array,
        description: "Individual entities to screen (blocklist + Watchman person search)",
        items: %Schema{
          type: :object,
          required: [:first_name, :last_name],
          properties: %{
            first_name: %Schema{type: :string},
            last_name: %Schema{type: :string},
            birth_date: %Schema{type: :string, nullable: true, description: "ISO 8601 date"},
            gender: %Schema{type: :string, nullable: true}
          }
        }
      },
      interested_companies: %Schema{
        type: :array,
        description: "Company entities to screen (blocklist + Watchman business search)",
        items: %Schema{
          type: :object,
          required: [:name],
          properties: %{
            name: %Schema{type: :string},
            created: %Schema{type: :string, nullable: true, description: "ISO 8601 date"},
            dissolved: %Schema{type: :string, nullable: true, description: "ISO 8601 date"}
          }
        }
      }
    },
    example: %{
      "account_holder_id" => "550e8400-e29b-41d4-a716-446655440000",
      "interested_individuals" => [
        %{"first_name" => "Jane", "last_name" => "Doe", "birth_date" => "1980-01-15"}
      ],
      "interested_companies" => [
        %{"name" => "Acme Corp", "created" => "2010-06-01"}
      ]
    }
  })
end
