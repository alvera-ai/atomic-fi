defmodule AtomicFiApi.TenantController do
  use AtomicFiApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.BlocklistContext.BlocklistCache
  alias AtomicFi.OpenApiSchema
  alias AtomicFi.OpenApiSchema.TenantListResponse
  alias AtomicFi.OpenApiSchema.TenantRequest
  alias AtomicFi.OpenApiSchema.TenantResponse
  alias AtomicFi.RoleContext.RoleConstants
  alias AtomicFi.TenantContext
  alias AtomicFiApi.Helpers.ApiHelpers
  alias ExOpenApiUtils
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback AtomicFiApi.FallbackController

  tags(["Tenants"])

  # Authorization helper
  defp authorize_platform_admin!(session) do
    if session.role && session.role.name == RoleConstants.platform_admin_api() do
      :ok
    else
      {:error, :forbidden}
    end
  end

  operation(:index,
    summary: "List tenants",
    description: """
    Returns a paginated list of tenants.

    Supports Flop pagination and filtering:
    - `page` - Page number (1-indexed, default: 1)
    - `page_size` - Items per page (default: 20, max: 100)
    - `order_by` - Field to sort by (name, slug, status, inserted_at, updated_at)
    - `order_directions` - Sort direction (asc or desc)

    Results are scoped to the authenticated tenant.
    """,
    parameters: [
      page: [
        in: :query,
        type: :integer,
        description: "Page number (1-indexed)",
        example: 1
      ],
      page_size: [
        in: :query,
        type: :integer,
        description: "Items per page (max: 100)",
        example: 20
      ],
      order_by: [
        in: :query,
        type: :string,
        description: "Field to sort by",
        example: "name"
      ],
      order_directions: [
        in: :query,
        type: :string,
        description: "Sort direction (asc or desc)",
        example: "asc"
      ]
    ],
    responses: [
      ok:
        {"Tenant list", "application/json",
         %Reference{"$ref": "#/components/schemas/TenantListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case TenantContext.list_tenants(session, flop_params) do
      {:ok, {tenants, meta}} ->
        ApiHelpers.json_paginated_response(conn, tenants, meta, TenantListResponse)

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get tenant by ID",
    description:
      "Returns a single tenant by ID. Tenant must belong to the authenticated user's scope.",
    parameters: [
      id: [
        in: :path,
        description: "Tenant ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Tenant", "application/json", %Reference{"$ref": "#/components/schemas/TenantResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    tenant = TenantContext.get_tenant!(session, id)

    ApiHelpers.json_response(conn, tenant, TenantResponse)
  end

  operation(:create,
    summary: "Create tenant",
    description: """
    Creates a new tenant.

    **Authorization**: Requires `platform_admin_api` role.

    **Note**: Only `standard` tenant type can be created via API. Platform tenants are created via migrations only.

    After creation, three default roles are automatically seeded:
    - `tenant_admin` - Full administrative access
    - `tenant_user` - Default role for human users
    - `tenant_api` - Default role for API keys
    """,
    request_body: {"Tenant params", "application/json", TenantRequest.schema(), required: true},
    responses: [
      created: {"Tenant created", "application/json", TenantResponse},
      forbidden: {"Insufficient permissions", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %TenantRequest{} = tenant_request} = conn, %{}) do
    session = conn.assigns.api_session

    with :ok <- authorize_platform_admin!(session),
         {:ok, tenant} <- TenantContext.create_tenant(session, tenant_request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/tenants/#{tenant.id}")
      |> ApiHelpers.json_response(tenant, TenantResponse)
    end
  end

  operation(:update,
    summary: "Update tenant (full replacement)",
    description: """
    Updates an existing tenant using PUT semantics (full replacement).

    **HTTP Method**: PUT only (PATCH not supported)
    **Semantics**: Send the complete resource representation. All fields should be provided.

    **Authorization**: Requires `platform_admin_api` role.

    **Security Note**: Changing `tenant_type` is not allowed for security reasons.

    **Required fields**: `name`, `tenant_type`
    """,
    parameters: [
      id: [
        in: :path,
        description: "Tenant ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body: {"Tenant params", "application/json", TenantRequest.schema(), required: true},
    responses: [
      ok: {"Tenant updated", "application/json", TenantResponse},
      forbidden: {"Insufficient permissions", "application/json", OpenApiSchema.ErrorResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(%{body_params: %TenantRequest{} = tenant_request} = conn, %{id: id}) do
    session = conn.assigns.api_session

    with :ok <- authorize_platform_admin!(session),
         tenant <- TenantContext.get_tenant!(session, id),
         {:ok, tenant} <- TenantContext.update_tenant(session, tenant, tenant_request) do
      ApiHelpers.json_response(conn, tenant, TenantResponse)
    end
  end

  operation(:delete,
    summary: "Delete tenant",
    description: """
    Deletes a tenant.

    **Authorization**: Requires `platform_admin_api` role.

    **Warning**: This operation will fail if the tenant has dependent records (roles, users, etc.)
    due to database foreign key constraints.
    """,
    parameters: [
      id: [
        in: :path,
        description: "Tenant ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Tenant deleted",
      forbidden: {"Insufficient permissions", "application/json", OpenApiSchema.ErrorResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      conflict: {"Constraint violation", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session

    with :ok <- authorize_platform_admin!(session) do
      tenant = TenantContext.get_tenant!(session, id)

      case TenantContext.delete_tenant(session, tenant) do
        {:ok, _tenant} ->
          send_resp(conn, :no_content, "")

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  operation(:refresh_blocklist_cache,
    summary: "Refresh blocklist cache",
    description: """
    Manually triggers a refresh of the blocklist cache for the authenticated tenant.

    This reloads all active blocklist entries from the database and rebuilds
    the ETS cache with optimized MapSets and combined regex patterns.

    **Note**: Cache is also automatically refreshed:
    - Every hour via Quantum scheduler
    - After create/update/delete operations on blocklist entries

    Use this endpoint when you need immediate cache refresh (e.g., after bulk imports).
    """,
    responses: [
      ok:
        {"Cache refreshed", "application/json",
         %Schema{
           type: :object,
           properties: %{
             message: %Schema{type: :string},
             tenant_id: %Schema{type: :string, format: :uuid}
           }
         }}
    ]
  )

  def refresh_blocklist_cache(conn, _params) do
    session = conn.assigns.api_session

    BlocklistCache.refresh_tenant_cache(session.tenant_id)

    json(conn, %{
      message: "Blocklist cache refreshed successfully",
      tenant_id: session.tenant_id
    })
  end
end
