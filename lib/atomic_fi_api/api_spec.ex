defmodule AtomicFiApi.ApiSpec do
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

      config :atomic_fi, :openapi_servers, [
        %{url: "http://localhost:4100", description: "Local development"},
        %{url: "https://api.example.com", description: "Production"}
      ]

  The description is automatically extracted from guides/introduction.md at compile time.
  """

  @behaviour OpenApiSpex.OpenApi

  alias AtomicFi.Config
  alias AtomicFi.OpenApiSchema
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
      paths: Paths.from_router(AtomicFiWeb.Router),
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
          # Request/Response schemas for Users
          "UserRequest" => OpenApiSchema.UserRequest.schema(),
          "UserResponse" => OpenApiSchema.UserResponse.schema(),
          "UserListResponse" => OpenApiSchema.UserListResponse.schema(),
          # Request/Response schemas for Roles
          "RoleRequest" => OpenApiSchema.RoleRequest.schema(),
          "RoleResponse" => OpenApiSchema.RoleResponse.schema(),
          "RoleListResponse" => OpenApiSchema.RoleListResponse.schema(),
          # Request/Response schemas for ApiKeys
          "ApiKeyRequest" => OpenApiSchema.ApiKeyRequest.schema(),
          "ApiKeyResponse" => OpenApiSchema.ApiKeyResponse.schema(),
          "ApiKeyListResponse" => OpenApiSchema.ApiKeyListResponse.schema(),
          # Request/Response schemas for Session (POST /api/sessions — email/password/tenant_slug
          # appear only in Request as writeOnly virtual fields)
          "SessionRequest" => OpenApiSchema.SessionRequest.schema(),
          "SessionResponse" => OpenApiSchema.SessionResponse.schema(),
          # Request/Response schemas for BlocklistEntry (tenant-managed internal blocklist)
          "BlocklistEntryRequest" => OpenApiSchema.BlocklistEntryRequest.schema(),
          "BlocklistEntryResponse" => OpenApiSchema.BlocklistEntryResponse.schema(),
          "BlocklistEntryListResponse" => OpenApiSchema.BlocklistEntryListResponse.schema(),
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
          "PaginationMeta" => OpenApiSchema.PaginationMeta.schema(),
          # Request/Response schemas for Ledger
          "LedgerRequest" => OpenApiSchema.LedgerRequest.schema(),
          "LedgerResponse" => OpenApiSchema.LedgerResponse.schema(),
          "LedgerListResponse" => OpenApiSchema.LedgerListResponse.schema(),
          # Request/Response schemas for LedgerAccount
          "LedgerAccountRequest" => OpenApiSchema.LedgerAccountRequest.schema(),
          "LedgerAccountResponse" => OpenApiSchema.LedgerAccountResponse.schema(),
          "LedgerAccountListResponse" => OpenApiSchema.LedgerAccountListResponse.schema(),
          # Request/Response schemas for LedgerEntry
          "LedgerEntryRequest" => OpenApiSchema.LedgerEntryRequest.schema(),
          "LedgerEntryResponse" => OpenApiSchema.LedgerEntryResponse.schema(),
          "LedgerEntryListResponse" => OpenApiSchema.LedgerEntryListResponse.schema(),
          # Response schemas for LedgerAccountBalance (read-only — trigger-maintained)
          "LedgerAccountBalanceResponse" => OpenApiSchema.LedgerAccountBalanceResponse.schema(),
          "LedgerAccountBalanceListResponse" =>
            OpenApiSchema.LedgerAccountBalanceListResponse.schema(),
          # Request/Response schemas for KycRequirement (FATF CDD/EDD/wire/UBO)
          "KycRequirementRequest" => OpenApiSchema.KycRequirementRequest.schema(),
          "KycRequirementResponse" => OpenApiSchema.KycRequirementResponse.schema(),
          "KycRequirementListResponse" => OpenApiSchema.KycRequirementListResponse.schema(),
          # Request/Response schemas for Document (ISO 20022 acmt:007 SupportingDocument)
          "DocumentRequest" => OpenApiSchema.DocumentRequest.schema(),
          "DocumentResponse" => OpenApiSchema.DocumentResponse.schema(),
          "DocumentListResponse" => OpenApiSchema.DocumentListResponse.schema(),
          # Request/Response schemas for PaymentAccount (ISO 20022 pain:001 DbtrAcct/CdtrAcct)
          "PaymentAccountRequest" => OpenApiSchema.PaymentAccountRequest.schema(),
          "PaymentAccountResponse" => OpenApiSchema.PaymentAccountResponse.schema(),
          "PaymentAccountListResponse" => OpenApiSchema.PaymentAccountListResponse.schema(),
          # Request/Response schemas for Transaction (ISO 20022 pain:001/pacs:008/002/004/camt:054)
          "TransactionRequest" => OpenApiSchema.TransactionRequest.schema(),
          "TransactionResponse" => OpenApiSchema.TransactionResponse.schema(),
          "TransactionListResponse" => OpenApiSchema.TransactionListResponse.schema(),
          # Request/Response schemas for AccountActivitySnapshot (ISO 20022 camt:052/053 · FinCEN AML)
          "AccountActivitySnapshotRequest" =>
            OpenApiSchema.AccountActivitySnapshotRequest.schema(),
          "AccountActivitySnapshotResponse" =>
            OpenApiSchema.AccountActivitySnapshotResponse.schema(),
          "AccountActivitySnapshotListResponse" =>
            OpenApiSchema.AccountActivitySnapshotListResponse.schema(),
          # Request/Response schemas for LegalEntityChangeEvent (ISO 20022 acmt:006/acmt:002 · AML)
          "LegalEntityChangeEventRequest" => OpenApiSchema.LegalEntityChangeEventRequest.schema(),
          "LegalEntityChangeEventResponse" =>
            OpenApiSchema.LegalEntityChangeEventResponse.schema(),
          "LegalEntityChangeEventListResponse" =>
            OpenApiSchema.LegalEntityChangeEventListResponse.schema(),
          # Request/Response schemas for PartyActivitySnapshot (FATF Rec 10 · FinCEN AML)
          "PartyActivitySnapshotRequest" => OpenApiSchema.PartyActivitySnapshotRequest.schema(),
          "PartyActivitySnapshotResponse" => OpenApiSchema.PartyActivitySnapshotResponse.schema(),
          "PartyActivitySnapshotListResponse" =>
            OpenApiSchema.PartyActivitySnapshotListResponse.schema(),
          # Request/Response schemas for RiskClassification (ISO 20022 auth:018 · FATF Rec 10)
          "RiskClassificationRequest" => OpenApiSchema.RiskClassificationRequest.schema(),
          "RiskClassificationResponse" => OpenApiSchema.RiskClassificationResponse.schema(),
          "RiskClassificationListResponse" =>
            OpenApiSchema.RiskClassificationListResponse.schema()
        }
      },
      tags: [
        %Tag{name: "Health", description: "System health and status"},
        %Tag{name: "Tenants", description: "Tenant management (requires API key)"},
        %Tag{
          name: "Users",
          description: "User management — email-authenticated accounts scoped to a tenant"
        },
        %Tag{
          name: "Roles",
          description: "Authorization roles (tenant-scoped) for users and API keys"
        },
        %Tag{
          name: "Api Keys",
          description:
            "Programmatic-access API keys. Each key has exactly one role. The plaintext key is returned ONCE on create — rotate by delete + create."
        },
        %Tag{
          name: "Auth",
          description:
            "Session lifecycle for human Bearer authentication — POST /api/sessions exchanges {email,password,tenant_slug} for a Bearer token; GET /verify returns the current identity; DELETE revokes the Bearer session. X-API-Key callers do not need these endpoints."
        },
        %Tag{
          name: "Blocklist Entries",
          description:
            "Tenant-managed internal blocklist — compliance officers add exact or regex terms " <>
              "to block by first_name, last_name, or company_name. The screening engine reads " <>
              "these at runtime via ETS cache (refreshed automatically on create/update/delete)."
        },
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
        },
        %Tag{
          name: "Ledgers",
          description:
            "ISO 20022 camt:052/camt:053 chart-of-accounts containers — one per AccountHolder per currency."
        },
        %Tag{
          name: "Ledger Accounts",
          description:
            "Chart-of-accounts line items within a Ledger (asset, liability, equity, revenue, expense). " <>
              "Stores running balance in minor currency units — atomically updated on entry create/reverse."
        },
        %Tag{
          name: "Ledger Entries",
          description:
            "Individual debit/credit line items (ISO 20022 CdtDbtInd). " <>
              "Creating an entry atomically updates the parent LedgerAccount balance via DB trigger. " <>
              "Voiding an entry (status → voided) reverses the balance delta. " <>
              "Velocity limits are enforced by DB CHECK constraints on ledger_account_balances."
        },
        %Tag{
          name: "Ledger Account Balances",
          description:
            "Daily balance snapshots for LedgerAccounts (read-only). " <>
              "Created and updated entirely by the ledger_entry_propagate_to_balances DB trigger. " <>
              "Each row carries day/week/month/year cumulative totals and last known velocity limits " <>
              "from the risk engine. Velocity limit enforcement is DB-driven via CHECK constraints."
        },
        %Tag{
          name: "KYC Requirements",
          description:
            "KYC verification requirements per FATF scope (CDD Rec 10 / EDD Rec 19 / wire Rec 16 / UBO Rec 24). " <>
              "One row per compliance check action — natural key: (account_holder_id, legal_entity_id, scope, requirement_type). " <>
              "account_holder_id is always the MDM subject; legal_entity_id is the identity being verified."
        },
        %Tag{
          name: "Documents",
          description:
            "Compliance supporting documents (ISO 20022 acmt:007 SupportingDocument). " <>
              "Identity documents, proof of address, UBO declarations, and other KYC artefacts linked to AccountHolders. " <>
              "Physical files are stored out-of-band; this API manages only storage references."
        },
        %Tag{
          name: "Payment Accounts",
          description:
            "Payment accounts linked to AccountHolders (ISO 20022 pain:001 <DbtrAcct>/<CdtrAcct>). " <>
              "Gates FATF Recommendation 16 wire transfer compliance. " <>
              "Supports bank accounts, cards, wallets, and crypto wallets. " <>
              "PCI-DSS 4.0: account_number, iban, card_pan must be tokenised before writing."
        },
        %Tag{
          name: "Transactions",
          description:
            "Payment transactions linked to AccountHolders — full ISO 20022 payment lifecycle. " <>
              "Covers pain:001 (initiation), pacs:008 (interbank), pacs:002 (status), " <>
              "pacs:004 (return/refund), camt:054 (booking notification). " <>
              "FATF Rec 16: debtor/creditor PaymentAccounts must be verified before settlement."
        },
        %Tag{
          name: "Account Activity Snapshots",
          description:
            "Periodic account activity summaries for AccountHolders (ISO 20022 camt:052/camt:053). " <>
              "Intraday snapshots map to camt:052 BankToCustomerAccountReport; " <>
              "daily/weekly/monthly snapshots map to camt:053 BankToCustomerStatement. " <>
              "AML fields (flagged_for_review, sar_reference) support FinCEN SAR filing under 31 CFR §1020.320."
        },
        %Tag{
          name: "Risk Classifications",
          description:
            "Formal risk-level records per AccountHolder (ISO 20022 auth:018 · FATF Rec 10). " <>
              "Drives the LedgerAccount limit cascade — the MASTER LedgerAccount velocity limit " <>
              "is a function of the active RiskClassification.risk_level. Exactly one is_active=true " <>
              "record exists per (holder, tenant) at a time; creating / activating a new one " <>
              "deactivates the prior active record atomically."
        },
        %Tag{
          name: "Party Activity Snapshots",
          description:
            "Period-level AML monitoring summaries for AccountHolders (FATF Rec 10 · " <>
              "FinCEN 31 CFR §1020.320). Captures KYC / risk-level transitions, screening " <>
              "activity, transaction shape, and SAR candidacy across a reporting window. " <>
              "Distinct from Account Activity Snapshots, which aggregate camt:052/053 ledger activity."
        },
        %Tag{
          name: "Legal Entity Change Events",
          description:
            "Audit log of non-financial identity lifecycle changes (ISO 20022 acmt:006/acmt:002). " <>
              "Auto-created by update_legal_entity via Ecto prepare_changes — captures JSONB diff and previous state. " <>
              "Primary AML signal source for account takeover detection: SIM swap (phone_change), " <>
              "address velocity (address_change), pre-transfer grooming (beneficiary_added/authorised_signer_change)."
        }
      ]
    }
  end

  defp servers do
    :openapi_servers
    |> Config.get([%{url: "http://localhost:4100", description: "Development server"}])
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
