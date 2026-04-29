defmodule AtomicFiApi.LegalEntityController do
  use AtomicFiApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.LegalEntityContext
  alias AtomicFi.OpenApiSchema
  alias AtomicFi.OpenApiSchema.LegalEntityListResponse
  alias AtomicFi.OpenApiSchema.LegalEntityRequest
  alias AtomicFi.OpenApiSchema.LegalEntityResponse
  alias AtomicFiApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback AtomicFiApi.FallbackController

  tags(["Legal Entities"])

  operation(:index,
    summary: "List legal entities",
    description: """
    Returns a paginated list of legal entities scoped to the authenticated tenant.

    Supports Flop pagination and filtering:
    - `page` - Page number (1-indexed, default: 1)
    - `page_size` - Items per page (default: 20, max: 100)
    - `order_by` - Field to sort by
    - `order_directions` - Sort direction (asc or desc)
    - `filters` - Flop filters (legal_entity_type, citizenship_country, politically_exposed_person)
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
        {"Legal entity list", "application/json",
         %Reference{"$ref": "#/components/schemas/LegalEntityListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case LegalEntityContext.list_legal_entities(session, flop_params) do
      {:ok, {legal_entities, meta}} ->
        ApiHelpers.json_paginated_response(conn, legal_entities, meta, LegalEntityListResponse)

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get legal entity by ID",
    description:
      "Returns a single legal entity with nested addresses, phone numbers, and identifications.",
    parameters: [
      id: [
        in: :path,
        description: "Legal entity ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Legal entity", "application/json",
         %Reference{"$ref": "#/components/schemas/LegalEntityResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    legal_entity = LegalEntityContext.get_legal_entity!(session, id)
    ApiHelpers.json_response(conn, legal_entity, LegalEntityResponse)
  end

  operation(:create,
    summary: "Create legal entity",
    description: """
    Creates a new legal entity with optional nested associations.

    Nested associations (addresses, phone_numbers, identifications) can be provided
    inline and will be created atomically with the parent entity.
    """,
    request_body:
      {"Legal entity params", "application/json", LegalEntityRequest.schema(), required: true},
    responses: [
      created: {"Legal entity created", "application/json", LegalEntityResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %LegalEntityRequest{} = legal_entity_request} = conn, %{}) do
    session = conn.assigns.api_session
    attrs = ExOpenApiUtils.Mapper.to_map(legal_entity_request)

    with {:ok, legal_entity} <-
           LegalEntityContext.create_legal_entity(session, attrs) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/legal-entities/#{legal_entity.id}")
      |> ApiHelpers.json_response(legal_entity, LegalEntityResponse)
    end
  end

  operation(:update,
    summary: "Update legal entity (full replacement)",
    description: """
    Updates an existing legal entity using PUT semantics (full replacement).

    Nested associations (addresses, phone_numbers, identifications) in the request
    body replace all existing associations for the entity.
    """,
    parameters: [
      id: [
        in: :path,
        description: "Legal entity ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body:
      {"Legal entity params", "application/json", LegalEntityRequest.schema(), required: true},
    responses: [
      ok: {"Legal entity updated", "application/json", LegalEntityResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(%{body_params: %LegalEntityRequest{} = legal_entity_request} = conn, %{id: id}) do
    session = conn.assigns.api_session
    attrs = ExOpenApiUtils.Mapper.to_map(legal_entity_request)
    legal_entity = LegalEntityContext.get_legal_entity!(session, id)

    with {:ok, legal_entity} <-
           LegalEntityContext.update_legal_entity(session, legal_entity, attrs) do
      ApiHelpers.json_response(conn, legal_entity, LegalEntityResponse)
    end
  end

  operation(:delete,
    summary: "Delete legal entity",
    description: """
    Deletes a legal entity and all associated addresses, phone numbers, and identifications
    (cascading delete via database foreign key constraints).
    """,
    parameters: [
      id: [
        in: :path,
        description: "Legal entity ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Legal entity deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    legal_entity = LegalEntityContext.get_legal_entity!(session, id)

    case LegalEntityContext.delete_legal_entity(session, legal_entity) do
      {:ok, _legal_entity} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
