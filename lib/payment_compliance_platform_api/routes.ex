defmodule PaymentCompliancePlatformApi.Routes do
  @moduledoc """
  REST API routes for Alvera Phoenix Template Server.

  All API routes are namespaced under `/api` with two categories:

  1. **Public Routes** - No authentication required
     - `/api/info` - API info with version and database status
     - `/api/openapi` - OpenAPI spec JSON
     - Pipe through: `:api` only

  2. **Protected Routes** - Require x-api-key header
     - `/api/tenants`, `/api/users`, etc.
     - Pipe through: `[:api, :api_authenticated]`
  """

  defmacro __using__(_) do
    quote do
      # Public API endpoints (no authentication)
      scope "/api", PaymentCompliancePlatformApi do
        pipe_through :api

        # API info endpoint (version + database connectivity check)
        get "/info", ApiInfoController, :info

        # Normalization rules endpoint (data quality rules)
        get "/info/normalization-rules", ApiInfoController, :normalization_rules

        # OpenAPI spec endpoint (for Scalar and other tools)
        get "/openapi", OpenApiSpecController, :spec
      end

      # Protected API routes - require x-api-key header
      scope "/api", PaymentCompliancePlatformApi do
        pipe_through [:api, :api_authenticated]

        # Tenant CRUD endpoints (PUT only for full replacement semantics)
        get "/tenants", TenantController, :index
        get "/tenants/:id", TenantController, :show
        post "/tenants", TenantController, :create
        put "/tenants/:id", TenantController, :update
        delete "/tenants/:id", TenantController, :delete

        # Tenant utility endpoints
        post "/tenants/refresh-blocklist-cache", TenantController, :refresh_blocklist_cache

        # Compliance screening CRUD + subject-specific screen actions (ISO 20022 auth:018 / camt:998)
        get "/compliance-screenings", ComplianceScreeningController, :index
        get "/compliance-screenings/:id", ComplianceScreeningController, :show
        put "/compliance-screenings/:id", ComplianceScreeningController, :update
        delete "/compliance-screenings/:id", ComplianceScreeningController, :delete

        post "/compliance-screenings/screen-account-holder",
             ComplianceScreeningController,
             :screen_account_holder

        post "/compliance-screenings/screen-beneficial-owner",
             ComplianceScreeningController,
             :screen_beneficial_owner

        post "/compliance-screenings/screen-counterparty",
             ComplianceScreeningController,
             :screen_counterparty

        # Legal entity CRUD endpoints (PUT only for full replacement semantics)
        get "/legal-entities", LegalEntityController, :index
        get "/legal-entities/:id", LegalEntityController, :show
        post "/legal-entities", LegalEntityController, :create
        put "/legal-entities/:id", LegalEntityController, :update
        delete "/legal-entities/:id", LegalEntityController, :delete

        # Account holder CRUD endpoints (PUT only for full replacement semantics)
        get "/account-holders", AccountHolderController, :index
        get "/account-holders/:id", AccountHolderController, :show
        post "/account-holders", AccountHolderController, :create
        put "/account-holders/:id", AccountHolderController, :update
        delete "/account-holders/:id", AccountHolderController, :delete

        # Beneficial owner CRUD endpoints (PUT only for full replacement semantics)
        get "/beneficial-owners", BeneficialOwnerController, :index
        get "/beneficial-owners/:id", BeneficialOwnerController, :show
        post "/beneficial-owners", BeneficialOwnerController, :create
        put "/beneficial-owners/:id", BeneficialOwnerController, :update
        delete "/beneficial-owners/:id", BeneficialOwnerController, :delete

        # Counterparty CRUD endpoints (PUT only for full replacement semantics)
        get "/counterparties", CounterpartyController, :index
        get "/counterparties/:id", CounterpartyController, :show
        post "/counterparties", CounterpartyController, :create
        put "/counterparties/:id", CounterpartyController, :update
        delete "/counterparties/:id", CounterpartyController, :delete

        # KYC requirement CRUD endpoints (FATF CDD/EDD/wire/UBO compliance verification)
        get "/kyc-requirements", KycRequirementController, :index
        get "/kyc-requirements/:id", KycRequirementController, :show
        post "/kyc-requirements", KycRequirementController, :create
        put "/kyc-requirements/:id", KycRequirementController, :update
        delete "/kyc-requirements/:id", KycRequirementController, :delete

        # Ledger CRUD endpoints (ISO 20022 camt:052/camt:053 — one per AccountHolder per currency)
        get "/ledgers", LedgerController, :index
        get "/ledgers/:id", LedgerController, :show
        post "/ledgers", LedgerController, :create
        put "/ledgers/:id", LedgerController, :update
        delete "/ledgers/:id", LedgerController, :delete

        # Ledger account CRUD endpoints (chart-of-accounts line items with stored balance)
        get "/ledger-accounts", LedgerAccountController, :index
        get "/ledger-accounts/:id", LedgerAccountController, :show
        post "/ledger-accounts", LedgerAccountController, :create
        put "/ledger-accounts/:id", LedgerAccountController, :update
        delete "/ledger-accounts/:id", LedgerAccountController, :delete

        # Ledger entry CRUD endpoints (debit/credit lines — balance updated atomically on create/void)
        get "/ledger-entries", LedgerEntryController, :index
        get "/ledger-entries/:id", LedgerEntryController, :show
        post "/ledger-entries", LedgerEntryController, :create
        put "/ledger-entries/:id", LedgerEntryController, :update
        delete "/ledger-entries/:id", LedgerEntryController, :delete

        # Ledger account balance read-only endpoints (trigger-maintained daily snapshots)
        get "/ledger-account-balances", LedgerAccountBalanceController, :index
        get "/ledger-account-balances/:id", LedgerAccountBalanceController, :show
      end
    end
  end
end
