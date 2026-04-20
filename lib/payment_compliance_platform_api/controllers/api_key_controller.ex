defmodule PaymentCompliancePlatformApi.ApiKeyController do
  use PaymentCompliancePlatformApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias PaymentCompliancePlatform.ApiKeyContext
  alias PaymentCompliancePlatform.OpenApiSchema
  alias PaymentCompliancePlatform.OpenApiSchema.ApiKeyListResponse
  alias PaymentCompliancePlatform.OpenApiSchema.ApiKeyRequest
  alias PaymentCompliancePlatform.OpenApiSchema.ApiKeyResponse
  alias PaymentCompliancePlatformApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback PaymentCompliancePlatformApi.FallbackController

  tags(["Api Keys"])

  operation(:index,
    summary: "List API keys",
    description: """
    Returns a paginated list of API keys scoped to the authenticated tenant.

    The plaintext key value is never returned — only key metadata (name, role, last_used_at).
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
        {"Api key list", "application/json",
         %Reference{"$ref": "#/components/schemas/ApiKeyListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case ApiKeyContext.list_api_keys(session, flop_params) do
      {:ok, {api_keys, meta}} ->
        ApiHelpers.json_paginated_response(conn, api_keys, meta, ApiKeyListResponse)

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get API key by ID",
    parameters: [
      id: [
        in: :path,
        description: "API key ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Api key", "application/json", %Reference{"$ref": "#/components/schemas/ApiKeyResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    api_key = ApiKeyContext.get_api_key!(session, id)
    ApiHelpers.json_response(conn, api_key, ApiKeyResponse)
  end

  operation(:create,
    summary: "Create API key",
    description: """
    Creates a new API key. The plaintext key is **server-generated** and returned in
    the `raw_key` field of the response — this is the ONLY time the plaintext is
    available. Store it securely client-side; it cannot be retrieved later.

    To rotate a key: delete the old one and create a new one.
    """,
    request_body: {"Api key params", "application/json", ApiKeyRequest.schema(), required: true},
    responses: [
      created: {"Api key created", "application/json", ApiKeyResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %ApiKeyRequest{} = api_key_request} = conn, %{}) do
    session = conn.assigns.api_session

    with {:ok, api_key} <- ApiKeyContext.generate_and_create_api_key(session, api_key_request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/api-keys/#{api_key.id}")
      |> ApiHelpers.json_response(api_key, ApiKeyResponse)
    end
  end

  operation(:delete,
    summary: "Delete API key",
    description: "Revokes the API key immediately. Subsequent requests using this key will fail.",
    parameters: [
      id: [
        in: :path,
        description: "API key ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Api key deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    api_key = ApiKeyContext.get_api_key!(session, id)

    case ApiKeyContext.delete_api_key(session, api_key) do
      {:ok, _api_key} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
