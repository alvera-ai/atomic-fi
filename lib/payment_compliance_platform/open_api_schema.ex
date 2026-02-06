defmodule PaymentCompliancePlatform.OpenApiSchema do
  @moduledoc """
  Common OpenAPI schemas for API responses.

  This module contains manually defined OpenAPI schemas that complement the
  auto-generated schemas from ExOpenApiUtils.

  ## Error Schemas

  - `ErrorResponse` - Generic error response
  - `ChangesetErrors` - Validation error response from Ecto changeset

  ## Pagination

  - `PaginationMeta` - Pagination metadata for list responses

  ## Health & Info

  - `ApiInfoResponse` - API information with version and database status
  - `ApiInfoErrorResponse` - API info error response when database check fails

  ## List Responses

  - `TenantListResponse` - Paginated list of tenants
  """

  alias OpenApiSpex.Schema

  defmodule PaginationMeta do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PaginationMeta",
      description: "Pagination metadata for list responses",
      type: :object,
      properties: %{
        page: %Schema{
          type: :integer,
          description: "Current page number (1-indexed)",
          example: 1
        },
        page_size: %Schema{
          type: :integer,
          description: "Number of items per page",
          example: 50
        },
        total_count: %Schema{
          type: :integer,
          description: "Total number of items across all pages",
          example: 125
        },
        total_pages: %Schema{
          type: :integer,
          description: "Total number of pages",
          example: 3
        }
      },
      required: [:page, :page_size, :total_count, :total_pages],
      example: %{
        "page" => 1,
        "page_size" => 50,
        "total_count" => 125,
        "total_pages" => 3
      }
    })
  end

  defmodule ErrorResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ErrorResponse",
      description: "Error response",
      type: :object,
      properties: %{
        errors: %Schema{
          type: :object,
          description:
            "Error details - values can be strings or arrays of strings (for validation errors)",
          additionalProperties: %Schema{
            oneOf: [
              %Schema{type: :string},
              %Schema{type: :array, items: %Schema{type: :string}}
            ]
          }
        }
      },
      example: %{
        "errors" => %{
          "detail" => "Not found"
        }
      }
    })
  end

  defmodule ChangesetErrors do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ChangesetErrors",
      description: "Validation error response in JSON:API format (from OpenApiSpex v2)",
      type: :object,
      properties: %{
        errors: %Schema{
          type: :array,
          description: "Array of validation error objects",
          items: %Schema{
            type: :object,
            properties: %{
              detail: %Schema{type: :string, description: "Error message"},
              source: %Schema{
                type: :object,
                properties: %{
                  pointer: %Schema{type: :string, description: "JSON pointer to the field"}
                }
              },
              title: %Schema{type: :string, description: "Error title"}
            }
          }
        }
      },
      example: %{
        "errors" => [
          %{
            "detail" => "can't be blank",
            "source" => %{"pointer" => "/name"},
            "title" => "Invalid value"
          },
          %{
            "detail" => "is invalid",
            "source" => %{"pointer" => "/type"},
            "title" => "Invalid value"
          }
        ]
      }
    })
  end

  defmodule ApiInfoResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ApiInfoResponse",
      description: "API information with version and database connectivity status",
      type: :object,
      properties: %{
        status: %Schema{type: :string, enum: ["ok", "error"], example: "ok"},
        version: %Schema{type: :string, example: "0.1.0"},
        database_status: %Schema{
          type: :string,
          enum: ["connected", "disconnected"],
          example: "connected"
        },
        timestamp: %Schema{
          type: :string,
          format: :"date-time",
          example: "2026-02-04T12:34:56.789Z"
        }
      },
      required: [:status, :version, :database_status, :timestamp]
    })
  end

  defmodule ApiInfoErrorResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ApiInfoErrorResponse",
      description: "API info error response when database check fails",
      type: :object,
      properties: %{
        status: %Schema{type: :string, enum: ["error"], example: "error"},
        version: %Schema{type: :string, example: "0.1.0"},
        database_status: %Schema{type: :string, enum: ["disconnected"], example: "disconnected"},
        error: %Schema{type: :string, example: "Database connection failed"},
        timestamp: %Schema{
          type: :string,
          format: :"date-time",
          example: "2026-02-04T12:34:56.789Z"
        }
      },
      required: [:status, :version, :database_status, :error, :timestamp]
    })
  end

  defmodule NormalizationRulesResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "NormalizationRulesResponse",
      description: "Data quality normalization rules used for account holder screening",
      type: :object,
      properties: %{
        titles: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Name titles to strip during normalization (e.g., Mr., Mrs., Dr.)",
          example: ["mr", "mrs", "ms", "dr", "prof"]
        },
        suffixes: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Name suffixes to standardize during normalization (e.g., Jr., Sr., III)",
          example: ["jr", "sr", "ii", "iii", "iv", "esq"]
        },
        entity_types: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description:
            "Company entity types to remove during normalization (e.g., LLC, Inc, Corp)",
          example: ["llc", "inc", "corp", "ltd", "llp"]
        }
      },
      required: [:titles, :suffixes, :entity_types],
      example: %{
        "titles" => ["mr", "mrs", "ms", "dr", "prof", "sir", "madam", "miss"],
        "suffixes" => ["jr", "sr", "ii", "iii", "iv", "v", "esq"],
        "entity_types" => ["llc", "inc", "corp", "ltd", "llp", "co", "company"]
      }
    })
  end

  # NOTE: TenantRequest and TenantResponse are auto-generated by ExOpenApiUtils
  # from PaymentCompliancePlatform.TenantContext.Tenant schema.
  # No manual definitions needed here.

  ## List Responses (using deflistresponse macro)
  require PaymentCompliancePlatform.OpenApiSchemaHelpers
  alias PaymentCompliancePlatform.OpenApiSchemaHelpers

  # Tenant list response - wraps TenantResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    TenantListResponse,
    TenantResponse,
    "tenants"
  )

  # BlocklistEntry list response - wraps BlocklistEntryResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    BlocklistEntryListResponse,
    BlocklistEntryResponse,
    "blocklist_entries"
  )
end
