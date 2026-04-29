defmodule AtomicFiApi.UserController do
  use AtomicFiApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.OpenApiSchema
  alias AtomicFi.OpenApiSchema.UserListResponse
  alias AtomicFi.OpenApiSchema.UserRequest
  alias AtomicFi.OpenApiSchema.UserResponse
  alias AtomicFi.UserContext
  alias AtomicFiApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback AtomicFiApi.FallbackController

  tags(["Users"])

  operation(:index,
    summary: "List users",
    description: """
    Returns a paginated list of users scoped to the authenticated tenant.

    Supports Flop pagination and filtering on `email`, `confirmed_at`.
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
        {"User list", "application/json",
         %Reference{"$ref": "#/components/schemas/UserListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case UserContext.list_users(session, flop_params) do
      {:ok, {users, meta}} ->
        ApiHelpers.json_paginated_response(conn, users, meta, UserListResponse)

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get user by ID",
    parameters: [
      id: [
        in: :path,
        description: "User ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok: {"User", "application/json", %Reference{"$ref": "#/components/schemas/UserResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    user = UserContext.get_user!(session, id)
    ApiHelpers.json_response(conn, user, UserResponse)
  end

  operation(:create,
    summary: "Create user",
    description: """
    Creates a new user. The `hashed_password` must be pre-hashed (bcrypt) by the caller.

    On success, the default tenant-level `user` role is automatically assigned.
    """,
    request_body: {"User params", "application/json", UserRequest.schema(), required: true},
    responses: [
      created: {"User created", "application/json", UserResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %UserRequest{} = user_request} = conn, %{}) do
    session = conn.assigns.api_session

    with {:ok, user} <- UserContext.create_user(session, user_request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/users/#{user.id}")
      |> ApiHelpers.json_response(user, UserResponse)
    end
  end

  operation(:update,
    summary: "Update user (full replacement)",
    parameters: [
      id: [
        in: :path,
        description: "User ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body: {"User params", "application/json", UserRequest.schema(), required: true},
    responses: [
      ok: {"User updated", "application/json", UserResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(%{body_params: %UserRequest{} = user_request} = conn, %{id: id}) do
    session = conn.assigns.api_session
    user = UserContext.get_user!(session, id)

    with {:ok, user} <- UserContext.update_user(session, user, user_request) do
      ApiHelpers.json_response(conn, user, UserResponse)
    end
  end

  operation(:delete,
    summary: "Delete user",
    parameters: [
      id: [
        in: :path,
        description: "User ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "User deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    user = UserContext.get_user!(session, id)

    case UserContext.delete_user(session, user) do
      {:ok, _user} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
