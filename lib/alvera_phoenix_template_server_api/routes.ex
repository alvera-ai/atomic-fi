defmodule AlveraPhoenixTemplateServerApi.Routes do
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
      scope "/api", AlveraPhoenixTemplateServerApi do
        pipe_through :api

        # API info endpoint (version + database connectivity check)
        get "/info", ApiInfoController, :info

        # OpenAPI spec endpoint (for Scalar and other tools)
        get "/openapi", OpenApiSpecController, :spec
      end

      # Protected API routes - require x-api-key header
      scope "/api", AlveraPhoenixTemplateServerApi do
        pipe_through [:api, :api_authenticated]

        # Tenant CRUD endpoints (PUT only for full replacement semantics)
        get "/tenants", TenantController, :index
        get "/tenants/:id", TenantController, :show
        post "/tenants", TenantController, :create
        put "/tenants/:id", TenantController, :update
        delete "/tenants/:id", TenantController, :delete

        # Future: Add more authenticated resources here
        # resources "/users", UserController, except: [:new, :edit]
      end
    end
  end
end
