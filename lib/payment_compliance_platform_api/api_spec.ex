defmodule PaymentCompliancePlatformApi.ApiSpec do
  @moduledoc """
  OpenAPI specification for the Alvera Phoenix Template Server API.

  This module defines the OpenAPI 3.1 specification for the API.
  It automatically generates API documentation from controller operations and schema definitions.

  The spec includes:
  - Server information from compile-time configuration
  - API metadata (title, version, description from guides/introduction.md)
  - Security schemes (x-api-key header authentication)
  - Paths generated from the router
  - Request/response schemas from annotated Ecto schemas

  ## Configuration

  Servers are configured in config/*.exs:

      config :payment_compliance_platform, :openapi_servers, [
        %{url: "http://localhost:4000", description: "Local development"},
        %{url: "https://api.example.com", description: "Production"}
      ]

  The description is automatically extracted from guides/introduction.md at compile time.
  """

  @behaviour OpenApiSpex.OpenApi

  alias PaymentCompliancePlatform.Config
  alias PaymentCompliancePlatform.OpenApiSchema
  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme, Server, Tag}

  @impl OpenApiSpex.OpenApi
  def spec do
    %OpenApi{
      openapi: "3.1.0",
      info: %Info{
        title: "Alvera Phoenix Template API",
        version: "0.1.0",
        description: read_description()
      },
      servers: servers(),
      paths: Paths.from_router(PaymentCompliancePlatformWeb.Router),
      components: %Components{
        securitySchemes: %{
          "ApiKeyAuth" => %SecurityScheme{
            type: "apiKey",
            name: "x-api-key",
            in: "header",
            description: "API key for authentication. Include as: x-api-key: your_api_key_here"
          }
        },
        schemas: %{
          # Health & Info schemas (used by assert_schema in tests)
          "ApiInfoResponse" => OpenApiSchema.ApiInfoResponse.schema(),
          "ApiInfoErrorResponse" => OpenApiSchema.ApiInfoErrorResponse.schema(),
          # Request/Response schemas for Tenants
          "TenantRequest" => OpenApiSchema.TenantRequest.schema(),
          "TenantResponse" => OpenApiSchema.TenantResponse.schema(),
          "TenantListResponse" => OpenApiSchema.TenantListResponse.schema(),
          # Common schemas
          "ErrorResponse" => OpenApiSchema.ErrorResponse.schema(),
          "ChangesetErrors" => OpenApiSchema.ChangesetErrors.schema(),
          "PaginationMeta" => OpenApiSchema.PaginationMeta.schema()
        }
      },
      tags: [
        %Tag{name: "Health", description: "System health and status"},
        %Tag{name: "Tenants", description: "Tenant management (requires API key)"},
        %Tag{name: "Users", description: "User management (requires API key)"},
        %Tag{
          name: "Customers",
          description: "Customer organization management (requires API key)"
        },
        %Tag{name: "Roles", description: "Role-based access control (requires API key)"},
        %Tag{name: "API Keys", description: "API key management (requires API key)"},
        %Tag{name: "Sessions", description: "Session management (requires API key)"}
      ]
    }
  end

  defp servers do
    :openapi_servers
    |> Config.get([%{url: "http://localhost:4000", description: "Development server"}])
    |> Enum.map(fn server_config ->
      %Server{
        url: server_config.url,
        description: server_config.description
      }
    end)
  end

  defp read_description do
    case File.read("guides/introduction.md") do
      {:ok, content} ->
        # Extract first paragraph or use full content
        content
        |> String.split("\n\n")
        |> List.first()
        |> String.trim()
        |> then(fn desc ->
          """
          #{desc}

          ## Authentication

          All protected API endpoints require API key authentication. Include your API key in the x-api-key header:

          ```
          x-api-key: your_api_key_here
          ```

          ## Multi-Tenancy

          All resources are scoped to a tenant. Requests automatically use the tenant associated with your API key.

          ## Pagination

          List endpoints support pagination using Flop parameters:
          - `page_size` - Number of items per page (default: 50)
          - `page` - Page number (1-indexed)
          - `order_by` - Fields to sort by
          - `order_directions` - Sort directions (asc/desc)
          """
        end)

      {:error, _} ->
        """
        Alvera Phoenix Template Server - A bare-bones Elixir/Phoenix template with multi-tenancy, RLS, and API-key authentication.

        ## Authentication

        All protected API endpoints require API key authentication. Include your API key in the x-api-key header:

        ```
        x-api-key: your_api_key_here
        ```

        ## Multi-Tenancy

        All resources are scoped to a tenant. Requests automatically use the tenant associated with your API key.
        """
    end
  end
end
