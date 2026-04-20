defmodule PaymentCompliancePlatformApi.RoleController do
  use PaymentCompliancePlatformApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias PaymentCompliancePlatform.OpenApiSchema
  alias PaymentCompliancePlatform.OpenApiSchema.RoleListResponse
  alias PaymentCompliancePlatform.OpenApiSchema.RoleRequest
  alias PaymentCompliancePlatform.OpenApiSchema.RoleResponse
  alias PaymentCompliancePlatform.RoleContext
  alias PaymentCompliancePlatformApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback PaymentCompliancePlatformApi.FallbackController

  tags(["Roles"])

  operation(:index,
    summary: "List roles",
    description: """
    Returns a paginated list of roles scoped to the authenticated tenant.

    Supports Flop pagination and filtering on `name`, `description`.
    """,
    parameters: [
      page: [in: :query, type: :integer, description: "Page number (1-indexed)", example: 1],
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
        example: "inserted_at"
      ],
      order_directions: [
        in: :query,
        type: :string,
        description: "Sort direction (asc or desc)",
        example: "desc"
      ]
    ],
    responses: [
      ok:
        {"Role list", "application/json",
         %Reference{"$ref": "#/components/schemas/RoleListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case RoleContext.list_roles(session, flop_params) do
      {:ok, {roles, meta}} ->
        ApiHelpers.json_paginated_response(conn, roles, meta, RoleListResponse)

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get role by ID",
    parameters: [
      id: [
        in: :path,
        description: "Role ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok: {"Role", "application/json", %Reference{"$ref": "#/components/schemas/RoleResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    role = RoleContext.get_role!(session, id)
    ApiHelpers.json_response(conn, role, RoleResponse)
  end

  operation(:create,
    summary: "Create role",
    description: """
    Creates a new role scoped to the authenticated tenant.

    Reserved role names (`root`, `platform_admin`, `system`, `system_api`) cannot be
    created through this endpoint — those are migration-managed. Customer-scoped roles
    require `customer_id`.
    """,
    request_body: {"Role params", "application/json", RoleRequest.schema(), required: true},
    responses: [
      created: {"Role created", "application/json", RoleResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %RoleRequest{} = role_request} = conn, %{}) do
    session = conn.assigns.api_session

    with {:ok, role} <- RoleContext.create_role(session, role_request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/roles/#{role.id}")
      |> ApiHelpers.json_response(role, RoleResponse)
    end
  end

  operation(:update,
    summary: "Update role (full replacement)",
    parameters: [
      id: [
        in: :path,
        description: "Role ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body: {"Role params", "application/json", RoleRequest.schema(), required: true},
    responses: [
      ok: {"Role updated", "application/json", RoleResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(%{body_params: %RoleRequest{} = role_request} = conn, %{id: id}) do
    session = conn.assigns.api_session
    role = RoleContext.get_role!(session, id)

    with {:ok, role} <- RoleContext.update_role(session, role, role_request) do
      ApiHelpers.json_response(conn, role, RoleResponse)
    end
  end

  operation(:delete,
    summary: "Delete role",
    parameters: [
      id: [
        in: :path,
        description: "Role ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Role deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    role = RoleContext.get_role!(session, id)

    case RoleContext.delete_role(session, role) do
      {:ok, _role} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
