defmodule AtomicFi.OpenApiSchema do
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
  # from AtomicFi.TenantContext.Tenant schema.
  # No manual definitions needed here.

  ## List Responses (using deflistresponse macro)
  require AtomicFi.OpenApiSchemaHelpers
  alias AtomicFi.OpenApiSchemaHelpers

  # Tenant list response - wraps TenantResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    TenantListResponse,
    TenantResponse,
    "tenants"
  )

  # User list response - wraps UserResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    UserListResponse,
    UserResponse,
    "users"
  )

  # Role list response - wraps RoleResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    RoleListResponse,
    RoleResponse,
    "roles"
  )

  # ApiKey list response - wraps ApiKeyResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    ApiKeyListResponse,
    ApiKeyResponse,
    "api_keys"
  )

  # BlocklistEntry list response - wraps BlocklistEntryResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    BlocklistEntryListResponse,
    BlocklistEntryResponse,
    "blocklist_entries"
  )

  # LegalEntity list response - wraps LegalEntityResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    LegalEntityListResponse,
    LegalEntityResponse,
    "legal_entities"
  )

  # AccountHolder list response - wraps AccountHolderResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    AccountHolderListResponse,
    AccountHolderResponse,
    "account_holders"
  )

  # BeneficialOwner list response - wraps BeneficialOwnerResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    BeneficialOwnerListResponse,
    BeneficialOwnerResponse,
    "beneficial_owners"
  )

  # Counterparty list response - wraps CounterpartyResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    CounterpartyListResponse,
    CounterpartyResponse,
    "counterparties"
  )

  # ComplianceScreening list response - wraps ComplianceScreeningResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    ComplianceScreeningListResponse,
    ComplianceScreeningResponse,
    "compliance_screenings"
  )

  # Ledger list response - wraps LedgerResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    LedgerListResponse,
    LedgerResponse,
    "ledgers"
  )

  # LedgerAccount list response - wraps LedgerAccountResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    LedgerAccountListResponse,
    LedgerAccountResponse,
    "ledger_accounts"
  )

  # LedgerEntry list response - wraps LedgerEntryResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    LedgerEntryListResponse,
    LedgerEntryResponse,
    "ledger_entries"
  )

  # LedgerAccountBalance list response - wraps LedgerAccountBalanceResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    LedgerAccountBalanceListResponse,
    LedgerAccountBalanceResponse,
    "ledger_account_balances"
  )

  # KycRequirement list response - wraps KycRequirementResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    KycRequirementListResponse,
    KycRequirementResponse,
    "kyc_requirements"
  )

  # Document list response - wraps DocumentResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    DocumentListResponse,
    DocumentResponse,
    "documents"
  )

  # PaymentAccount list response - wraps PaymentAccountResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    PaymentAccountListResponse,
    PaymentAccountResponse,
    "payment_accounts"
  )

  # Transaction list response - wraps TransactionResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    TransactionListResponse,
    TransactionResponse,
    "transactions"
  )

  # AccountActivitySnapshot list response - wraps AccountActivitySnapshotResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    AccountActivitySnapshotListResponse,
    AccountActivitySnapshotResponse,
    "account_activity_snapshots"
  )

  # LegalEntityChangeEvent list response - wraps LegalEntityChangeEventResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    LegalEntityChangeEventListResponse,
    LegalEntityChangeEventResponse,
    "legal_entity_change_events"
  )

  # PartyActivitySnapshot list response - wraps PartyActivitySnapshotResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    PartyActivitySnapshotListResponse,
    PartyActivitySnapshotResponse,
    "party_activity_snapshots"
  )

  # RiskClassification list response - wraps RiskClassificationResponse in paginated format
  OpenApiSchemaHelpers.deflistresponse(
    RiskClassificationListResponse,
    RiskClassificationResponse,
    "risk_classifications"
  )

  # -- Document parser (`POST /api/parse`) ---------------------------
  #
  # The request body is `application/json` with a `files` array; each
  # entry carries the document bytes as base64 (`format: byte` per
  # OpenAPI spec). Mirrors the Python service's multipart contract on
  # the response side so the onboarding-flow client's decoder is
  # unchanged.

  defmodule ParseRequestFile do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ParseRequestFile",
      description: "One file in a /api/parse request — base64-encoded bytes + metadata.",
      type: :object,
      properties: %{
        name: %Schema{type: :string, description: "Filename (used in the response)"},
        content_type: %Schema{
          type: :string,
          description: "MIME type — application/pdf or image/*",
          example: "image/png"
        },
        document_type: %Schema{
          type: :string,
          enum: [
            "passport",
            "driving_licence",
            "national_id",
            "visa",
            "bank_statement",
            "memorandum",
            "custom"
          ]
        },
        data_base64: %Schema{
          type: :string,
          format: :byte,
          description: "Document bytes, base64-encoded (standard OpenAPI binary-as-string)."
        },
        label: %Schema{
          type: :string,
          nullable: true,
          description: "Optional caller-supplied label echoed in the response."
        },
        output_schema: %Schema{
          type: :object,
          nullable: true,
          additionalProperties: true,
          description:
            "Required when document_type='custom' — the JSON Schema to extract against."
        },
        prompt: %Schema{
          type: :string,
          nullable: true,
          description: "Optional extraction-prompt override."
        }
      },
      required: [:name, :content_type, :document_type, :data_base64]
    })
  end

  defmodule ParseRequest do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ParseRequest",
      description: "POST /api/parse — extract structured data from one or more documents.",
      type: :object,
      properties: %{
        files: %Schema{
          type: :array,
          items: %OpenApiSpex.Reference{"$ref": "#/components/schemas/ParseRequestFile"},
          minItems: 1,
          description: "Documents to extract — one entry per file."
        }
      },
      required: [:files]
    })
  end

  defmodule ParseUsageInfo do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ParseUsageInfo",
      description: "LLM token-usage info for one extraction.",
      type: :object,
      properties: %{
        input_tokens: %Schema{type: :integer, nullable: true},
        output_tokens: %Schema{type: :integer, nullable: true},
        total_tokens: %Schema{type: :integer, nullable: true}
      }
    })
  end

  defmodule ExtractionResult do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ExtractionResult",
      description: "Result for one file in a /api/parse response.",
      type: :object,
      properties: %{
        filename: %Schema{type: :string},
        document_type: %Schema{type: :string},
        success: %Schema{type: :boolean},
        data: %Schema{
          type: :object,
          nullable: true,
          additionalProperties: true,
          description: "Extracted structured data matching the schema for the document_type."
        },
        error: %Schema{type: :string, nullable: true},
        usage: %OpenApiSpex.Reference{"$ref": "#/components/schemas/ParseUsageInfo"}
      },
      required: [:filename, :document_type, :success]
    })
  end

  defmodule ParseResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ParseResponse",
      description: "POST /api/parse response — one ExtractionResult per input file.",
      type: :object,
      properties: %{
        results: %Schema{
          type: :array,
          items: %OpenApiSpex.Reference{"$ref": "#/components/schemas/ExtractionResult"}
        }
      },
      required: [:results]
    })
  end
end
