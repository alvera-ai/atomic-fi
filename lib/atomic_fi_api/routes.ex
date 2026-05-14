defmodule AtomicFiApi.Routes do
  @moduledoc """
  REST API routes for Payments Compliance Platform.

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
      scope "/api", AtomicFiApi do
        pipe_through :api

        # API info endpoint (version + database connectivity check)
        get "/info", ApiInfoController, :info

        # Normalization rules endpoint (data quality rules)
        get "/info/normalization-rules", ApiInfoController, :normalization_rules

        # OpenAPI spec endpoint (for Scalar and other tools)
        get "/openapi", OpenApiSpecController, :spec

        # Bearer session creation (exchange credentials for Bearer token)
        post "/sessions", SessionController, :create
      end

      # Protected API routes - require x-api-key header
      scope "/api", AtomicFiApi do
        pipe_through [:api, :api_authenticated]

        # Tenant CRUD endpoints (PUT only for full replacement semantics)
        get "/tenants", TenantController, :index
        get "/tenants/:id", TenantController, :show
        post "/tenants", TenantController, :create
        put "/tenants/:id", TenantController, :update
        delete "/tenants/:id", TenantController, :delete

        # Tenant utility endpoints
        post "/tenants/refresh-blocklist-cache", TenantController, :refresh_blocklist_cache

        # User CRUD endpoints (PUT only for full replacement semantics)
        resources "/users", UserController, only: [:index, :show, :create, :update, :delete]

        # Role CRUD endpoints (tenant-scoped authorization roles)
        resources "/roles", RoleController, only: [:index, :show, :create, :update, :delete]

        # API Key endpoints — no PUT (rotate via delete + create)
        resources "/api-keys", ApiKeyController, only: [:index, :show, :create, :delete]

        # Session endpoints (Bearer lifecycle)
        get "/sessions/verify", SessionController, :verify
        delete "/sessions", SessionController, :delete

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

        post "/compliance-screenings/screen-payment-account",
             ComplianceScreeningController,
             :screen_payment_account

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

        # Rule (JDM) file CRUD — thin REST shim over RulesContext / shared
        # ZenRule volume. rule_type is the kebab-case folder slug.
        get "/rules/:rule_type", RuleController, :index
        get "/rules/:rule_type/:name", RuleController, :show
        put "/rules/:rule_type/:name", RuleController, :update
        delete "/rules/:rule_type/:name", RuleController, :delete

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

        # Document CRUD endpoints (ISO 20022 acmt:007 SupportingDocument — KYC artefacts)
        get "/documents", DocumentController, :index
        get "/documents/:id", DocumentController, :show
        post "/documents", DocumentController, :create
        put "/documents/:id", DocumentController, :update
        delete "/documents/:id", DocumentController, :delete

        # Payment account CRUD endpoints (ISO 20022 pain:001 DbtrAcct/CdtrAcct — FATF Rec 16)
        get "/payment-accounts", PaymentAccountController, :index
        get "/payment-accounts/:id", PaymentAccountController, :show
        post "/payment-accounts", PaymentAccountController, :create
        put "/payment-accounts/:id", PaymentAccountController, :update
        delete "/payment-accounts/:id", PaymentAccountController, :delete

        # Transaction CRUD endpoints (ISO 20022 pain:001/pacs:008/002/004/camt:054)
        get "/transactions", TransactionController, :index
        get "/transactions/:id", TransactionController, :show
        post "/transactions", TransactionController, :create
        put "/transactions/:id", TransactionController, :update
        delete "/transactions/:id", TransactionController, :delete

        # Account activity snapshot CRUD endpoints (ISO 20022 camt:052/053 · FinCEN AML)
        get "/account-activity-snapshots", AccountActivitySnapshotController, :index
        get "/account-activity-snapshots/:id", AccountActivitySnapshotController, :show
        post "/account-activity-snapshots", AccountActivitySnapshotController, :create
        put "/account-activity-snapshots/:id", AccountActivitySnapshotController, :update
        delete "/account-activity-snapshots/:id", AccountActivitySnapshotController, :delete

        # Blocklist entry CRUD endpoints (tenant-managed internal blocklist — cache auto-refreshes)
        get "/blocklist-entries", BlocklistEntryController, :index
        get "/blocklist-entries/:id", BlocklistEntryController, :show
        post "/blocklist-entries", BlocklistEntryController, :create
        put "/blocklist-entries/:id", BlocklistEntryController, :update
        delete "/blocklist-entries/:id", BlocklistEntryController, :delete

        # Risk classification CRUD endpoints (ISO 20022 auth:018 · FATF Rec 10)
        get "/risk-classifications", RiskClassificationController, :index
        get "/risk-classifications/:id", RiskClassificationController, :show
        post "/risk-classifications", RiskClassificationController, :create
        put "/risk-classifications/:id", RiskClassificationController, :update
        delete "/risk-classifications/:id", RiskClassificationController, :delete

        # Party activity snapshot CRUD endpoints (FATF Rec 10 · FinCEN AML period snapshot)
        get "/party-activity-snapshots", PartyActivitySnapshotController, :index
        get "/party-activity-snapshots/:id", PartyActivitySnapshotController, :show
        post "/party-activity-snapshots", PartyActivitySnapshotController, :create
        put "/party-activity-snapshots/:id", PartyActivitySnapshotController, :update
        delete "/party-activity-snapshots/:id", PartyActivitySnapshotController, :delete

        # Legal entity change event CRUD endpoints (ISO 20022 acmt:006/acmt:002 · AML account takeover)
        get "/legal-entity-change-events", LegalEntityChangeEventController, :index
        get "/legal-entity-change-events/:id", LegalEntityChangeEventController, :show
        post "/legal-entity-change-events", LegalEntityChangeEventController, :create
        put "/legal-entity-change-events/:id", LegalEntityChangeEventController, :update
        delete "/legal-entity-change-events/:id", LegalEntityChangeEventController, :delete
      end
    end
  end
end
