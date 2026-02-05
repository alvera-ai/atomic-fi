defmodule PaymentCompliancePlatformApi.Schemas do
  @moduledoc """
  Common OpenAPI schemas used across the API.

  This module defines reusable schemas for request/response objects
  that are used by multiple endpoints.
  """

  alias OpenApiSpex.Schema

  defmodule ErrorResponse do
    @moduledoc "Schema for error responses"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ErrorResponse",
      description: "Standard error response format",
      type: :object,
      properties: %{
        errors: %Schema{
          type: :object,
          description: "Map of field names to error messages",
          additionalProperties: %Schema{
            oneOf: [
              %Schema{type: :string},
              %Schema{type: :array, items: %Schema{type: :string}}
            ]
          }
        }
      },
      required: [:errors],
      example: %{
        errors: %{
          email: ["can't be blank"],
          password: ["should be at least 8 character(s)"]
        }
      }
    })
  end

  defmodule PaginationMeta do
    @moduledoc "Schema for pagination metadata"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PaginationMeta",
      description: "Pagination metadata",
      type: :object,
      properties: %{
        total: %Schema{type: :integer, description: "Total number of items"},
        page: %Schema{type: :integer, description: "Current page number"},
        page_size: %Schema{type: :integer, description: "Items per page"},
        total_pages: %Schema{type: :integer, description: "Total number of pages"}
      },
      required: [:total, :page, :page_size, :total_pages],
      example: %{
        total: 42,
        page: 1,
        page_size: 10,
        total_pages: 5
      }
    })
  end

  defmodule HealthCheck do
    @moduledoc "Schema for health check response"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "HealthCheck",
      description: "API health check response",
      type: :object,
      properties: %{
        status: %Schema{type: :string, enum: ["ok", "error"]},
        version: %Schema{type: :string},
        timestamp: %Schema{type: :string, format: :"date-time"}
      },
      required: [:status],
      example: %{
        status: "ok",
        version: "1.0.0",
        timestamp: "2024-01-01T00:00:00Z"
      }
    })
  end
end
