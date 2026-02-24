defmodule PaymentCompliancePlatformApi.ApiSpec do
  @moduledoc """
  OpenAPI specification for the Payment Compliance Platform API.

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
        title: "Payment Compliance Platform API",
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
          "NormalizationRulesResponse" => OpenApiSchema.NormalizationRulesResponse.schema(),
          # Request/Response schemas for Tenants
          "TenantRequest" => OpenApiSchema.TenantRequest.schema(),
          "TenantResponse" => OpenApiSchema.TenantResponse.schema(),
          "TenantListResponse" => OpenApiSchema.TenantListResponse.schema(),
          # Request/Response schemas for AccountHolder
          "AccountHolderRequest" => OpenApiSchema.AccountHolderRequest.schema(),
          "AccountHolderResponse" => OpenApiSchema.AccountHolderResponse.schema(),
          "AccountHolderListResponse" => OpenApiSchema.AccountHolderListResponse.schema(),
          # Request/Response schemas for BeneficialOwner
          "BeneficialOwnerRequest" => OpenApiSchema.BeneficialOwnerRequest.schema(),
          "BeneficialOwnerResponse" => OpenApiSchema.BeneficialOwnerResponse.schema(),
          "BeneficialOwnerListResponse" => OpenApiSchema.BeneficialOwnerListResponse.schema(),
          # Request/Response schemas for Counterparty
          "CounterpartyRequest" => OpenApiSchema.CounterpartyRequest.schema(),
          "CounterpartyResponse" => OpenApiSchema.CounterpartyResponse.schema(),
          "CounterpartyListResponse" => OpenApiSchema.CounterpartyListResponse.schema(),
          # Nested schemas for AccountHolder
          "InterestedCompanyRequest" => OpenApiSchema.InterestedCompanyRequest.schema(),
          "InterestedCompanyResponse" => OpenApiSchema.InterestedCompanyResponse.schema(),
          "InterestedIndividualRequest" => OpenApiSchema.InterestedIndividualRequest.schema(),
          "InterestedIndividualResponse" => OpenApiSchema.InterestedIndividualResponse.schema(),
          # Watchman nested schemas
          "AddressRequest" => OpenApiSchema.AddressRequest.schema(),
          "AddressResponse" => OpenApiSchema.AddressResponse.schema(),
          "ContactRequest" => OpenApiSchema.ContactRequest.schema(),
          "ContactResponse" => OpenApiSchema.ContactResponse.schema(),
          # Request/Response schemas for ComplianceScreening (ISO 20022 auth:018 / camt:998)
          "ComplianceScreeningRequest" => OpenApiSchema.ComplianceScreeningRequest.schema(),
          "ComplianceScreeningResponse" => OpenApiSchema.ComplianceScreeningResponse.schema(),
          "ComplianceScreeningListResponse" =>
            OpenApiSchema.ComplianceScreeningListResponse.schema(),
          # Manual ScreeningRequest struct (input-only for screen_* controller actions)
          "ScreeningRequest" =>
            PaymentCompliancePlatform.ComplianceScreeningContext.ScreeningRequest.schema(),
          "SanctionsMatchRequest" => OpenApiSchema.SanctionsMatchRequest.schema(),
          "SanctionsMatchResponse" => OpenApiSchema.SanctionsMatchResponse.schema(),
          "BlocklistMatchRequest" => OpenApiSchema.BlocklistMatchRequest.schema(),
          "BlocklistMatchResponse" => OpenApiSchema.BlocklistMatchResponse.schema(),
          # Watchman typed embed schemas (auto-generated from SanctionsMatch inline modules)
          "WatchmanAddressRequest" => OpenApiSchema.WatchmanAddressRequest.schema(),
          "WatchmanAddressResponse" => OpenApiSchema.WatchmanAddressResponse.schema(),
          "WatchmanBusinessRequest" => OpenApiSchema.WatchmanBusinessRequest.schema(),
          "WatchmanBusinessResponse" => OpenApiSchema.WatchmanBusinessResponse.schema(),
          "WatchmanPersonRequest" => OpenApiSchema.WatchmanPersonRequest.schema(),
          "WatchmanPersonResponse" => OpenApiSchema.WatchmanPersonResponse.schema(),
          "WatchmanContactRequest" => OpenApiSchema.WatchmanContactRequest.schema(),
          "WatchmanContactResponse" => OpenApiSchema.WatchmanContactResponse.schema(),
          # Request/Response schemas for LegalEntity
          "LegalEntityRequest" => OpenApiSchema.LegalEntityRequest.schema(),
          "LegalEntityResponse" => OpenApiSchema.LegalEntityResponse.schema(),
          "LegalEntityListResponse" => OpenApiSchema.LegalEntityListResponse.schema(),
          # Nested schemas for LegalEntity
          "LegalEntityAddressRequest" => OpenApiSchema.LegalEntityAddressRequest.schema(),
          "LegalEntityAddressResponse" => OpenApiSchema.LegalEntityAddressResponse.schema(),
          "LegalEntityPhoneNumberRequest" => OpenApiSchema.LegalEntityPhoneNumberRequest.schema(),
          "LegalEntityPhoneNumberResponse" =>
            OpenApiSchema.LegalEntityPhoneNumberResponse.schema(),
          "LegalEntityIdentificationRequest" =>
            OpenApiSchema.LegalEntityIdentificationRequest.schema(),
          "LegalEntityIdentificationResponse" =>
            OpenApiSchema.LegalEntityIdentificationResponse.schema(),
          # Common schemas
          "ErrorResponse" => OpenApiSchema.ErrorResponse.schema(),
          "ChangesetErrors" => OpenApiSchema.ChangesetErrors.schema(),
          "PaginationMeta" => OpenApiSchema.PaginationMeta.schema()
        }
      },
      tags: [
        %Tag{name: "Health", description: "System health and status"},
        %Tag{name: "Tenants", description: "Tenant management (requires API key)"},
        %Tag{
          name: "Compliance Screening",
          description:
            "ISO 20022 compliance screening — sanctions (OFAC/Watchman), PEP, AML, blocklist (auth:018 / camt:998)"
        },
        %Tag{
          name: "Legal Entities",
          description: "Legal entity identity records (ISO 20022 acmt:007 + FATF CDD)"
        },
        %Tag{
          name: "Account Holders",
          description:
            "Account holder operational state (ISO 20022 acmt:007 / acmt:019). " <>
              "PII lives in the linked Legal Entity."
        },
        %Tag{
          name: "Beneficial Owners",
          description:
            "Beneficial owners of corporate account holders (FinCEN CDD Rule 31 CFR §1010.230 / FATF Rec 24). " <>
              "PII lives in the linked Legal Entity."
        },
        %Tag{
          name: "Counterparties",
          description:
            "External payers/payees (ISO 20022 <Dbtr>/<Cdtr>) that AccountHolders transact with. " <>
              "PII lives in the linked Legal Entity."
        }
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
        Payment Compliance Platform - Screen payments and account holders against international sanctions lists with manual review and override capabilities.

        ## Authentication

        All protected API endpoints require API key authentication. Include your API key in the x-api-key header:

        ```
        x-api-key: your_api_key_here
        ```

        ## Multi-Tenancy

        All resources are scoped to a tenant (financial institution). Requests automatically use the tenant associated with your API key.
        """
    end
  end
end
