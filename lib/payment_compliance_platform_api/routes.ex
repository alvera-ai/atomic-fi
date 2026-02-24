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

        # Onboarding screening endpoint
        post "/onboarding/screen", OnboardingController, :screen

        # Legal entity CRUD endpoints (PUT only for full replacement semantics)
        get "/legal-entities", LegalEntityController, :index
        get "/legal-entities/:id", LegalEntityController, :show
        post "/legal-entities", LegalEntityController, :create
        put "/legal-entities/:id", LegalEntityController, :update
        delete "/legal-entities/:id", LegalEntityController, :delete
      end
    end
  end
end
