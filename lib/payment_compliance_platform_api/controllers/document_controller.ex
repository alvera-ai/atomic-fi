defmodule PaymentCompliancePlatformApi.DocumentController do
  use PaymentCompliancePlatformApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias PaymentCompliancePlatform.DocumentContext
  alias PaymentCompliancePlatform.OpenApiSchema
  alias PaymentCompliancePlatform.OpenApiSchema.DocumentListResponse
  alias PaymentCompliancePlatform.OpenApiSchema.DocumentRequest
  alias PaymentCompliancePlatform.OpenApiSchema.DocumentResponse
  alias PaymentCompliancePlatformApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback PaymentCompliancePlatformApi.FallbackController

  tags(["Documents"])

  operation(:index,
    summary: "List documents",
    description: """
    Returns a paginated list of compliance documents scoped to the authenticated tenant.

    Supports Flop pagination and filtering:
    - `page` - Page number (1-indexed, default: 1)
    - `page_size` - Items per page (default: 20, max: 100)
    - `order_by` - Field to sort by
    - `order_directions` - Sort direction (asc or desc)
    - `filters` - Flop filters (account_holder_id, document_type, status, primary, name)
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
        {"Document list", "application/json",
         %Reference{"$ref": "#/components/schemas/DocumentListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case DocumentContext.list_documents(session, flop_params) do
      {:ok, {documents, meta}} ->
        ApiHelpers.json_paginated_response(conn, documents, meta, DocumentListResponse)

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get document by ID",
    description: "Returns a single compliance document.",
    parameters: [
      id: [
        in: :path,
        description: "Document ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Document", "application/json",
         %Reference{"$ref": "#/components/schemas/DocumentResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    document = DocumentContext.get_document!(session, id)
    ApiHelpers.json_response(conn, document, DocumentResponse)
  end

  operation(:create,
    summary: "Create document",
    description: """
    Creates a new compliance document for an AccountHolder.

    Physical file storage is handled out-of-band — this endpoint only records the
    storage reference (`file_key`, `file_name`, `content_type`, `file_size`).

    At most one document may be `primary = true` per `(account_holder_id, name)` combination.
    A secondary (`primary = false`) may not be created until a primary exists.
    """,
    request_body:
      {"Document params", "application/json", DocumentRequest.schema(), required: true},
    responses: [
      created: {"Document created", "application/json", DocumentResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %DocumentRequest{} = request} = conn, %{}) do
    session = conn.assigns.api_session

    with {:ok, document} <- DocumentContext.create_document(session, request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/documents/#{document.id}")
      |> ApiHelpers.json_response(document, DocumentResponse)
    end
  end

  operation(:update,
    summary: "Update document (full replacement)",
    description:
      "Updates an existing compliance document using PUT semantics (full replacement).",
    parameters: [
      id: [
        in: :path,
        description: "Document ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body:
      {"Document params", "application/json", DocumentRequest.schema(), required: true},
    responses: [
      ok: {"Document updated", "application/json", DocumentResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(%{body_params: %DocumentRequest{} = request} = conn, %{id: id}) do
    session = conn.assigns.api_session
    document = DocumentContext.get_document!(session, id)

    with {:ok, document} <- DocumentContext.update_document(session, document, request) do
      ApiHelpers.json_response(conn, document, DocumentResponse)
    end
  end

  operation(:delete,
    summary: "Delete document",
    description: "Deletes a compliance document.",
    parameters: [
      id: [
        in: :path,
        description: "Document ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Document deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    document = DocumentContext.get_document!(session, id)

    case DocumentContext.delete_document(session, document) do
      {:ok, _document} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
