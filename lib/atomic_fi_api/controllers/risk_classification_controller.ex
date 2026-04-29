defmodule AtomicFiApi.RiskClassificationController do
  use AtomicFiApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.OpenApiSchema
  alias AtomicFi.OpenApiSchema.RiskClassificationListResponse
  alias AtomicFi.OpenApiSchema.RiskClassificationRequest
  alias AtomicFi.OpenApiSchema.RiskClassificationResponse
  alias AtomicFi.RiskClassificationContext
  alias AtomicFiApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback AtomicFiApi.FallbackController

  tags(["Risk Classifications"])

  operation(:index,
    summary: "List risk classifications",
    description: """
    Returns a paginated list of risk classifications scoped to the authenticated tenant.

    Supports Flop filtering on account_holder_id, risk_level, is_active, effective_from/until.
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
        example: "effective_from"
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
        {"Risk classification list", "application/json",
         %Reference{"$ref": "#/components/schemas/RiskClassificationListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case RiskClassificationContext.list_risk_classifications(session, flop_params) do
      {:ok, {classifications, meta}} ->
        ApiHelpers.json_paginated_response(
          conn,
          classifications,
          meta,
          RiskClassificationListResponse
        )

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get risk classification by ID",
    parameters: [
      id: [
        in: :path,
        description: "Risk classification ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Risk classification", "application/json",
         %Reference{"$ref": "#/components/schemas/RiskClassificationResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    classification = RiskClassificationContext.get_risk_classification!(session, id)
    ApiHelpers.json_response(conn, classification, RiskClassificationResponse)
  end

  operation(:create,
    summary: "Create risk classification",
    description: """
    Creates a new risk classification for an AccountHolder. When `is_active: true`
    (the default), any previously active classification for the same holder is
    deactivated atomically so the single-active invariant is preserved.
    """,
    request_body:
      {"Risk classification params", "application/json", RiskClassificationRequest.schema(),
       required: true},
    responses: [
      created: {"Risk classification created", "application/json", RiskClassificationResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %RiskClassificationRequest{} = request} = conn, %{}) do
    session = conn.assigns.api_session

    with {:ok, classification} <-
           RiskClassificationContext.create_risk_classification(session, request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/risk-classifications/#{classification.id}")
      |> ApiHelpers.json_response(classification, RiskClassificationResponse)
    end
  end

  operation(:update,
    summary: "Update risk classification (full replacement)",
    description: """
    Updates an existing risk classification. When an inactive record is being
    activated (is_active: false → true), any other active classification for the
    same holder is deactivated atomically.
    """,
    parameters: [
      id: [
        in: :path,
        description: "Risk classification ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body:
      {"Risk classification params", "application/json", RiskClassificationRequest.schema(),
       required: true},
    responses: [
      ok: {"Risk classification updated", "application/json", RiskClassificationResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(%{body_params: %RiskClassificationRequest{} = request} = conn, %{id: id}) do
    session = conn.assigns.api_session
    classification = RiskClassificationContext.get_risk_classification!(session, id)

    with {:ok, classification} <-
           RiskClassificationContext.update_risk_classification(
             session,
             classification,
             request
           ) do
      ApiHelpers.json_response(conn, classification, RiskClassificationResponse)
    end
  end

  operation(:delete,
    summary: "Delete risk classification",
    parameters: [
      id: [
        in: :path,
        description: "Risk classification ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Risk classification deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    classification = RiskClassificationContext.get_risk_classification!(session, id)

    case RiskClassificationContext.delete_risk_classification(session, classification) do
      {:ok, _classification} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
