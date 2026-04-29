defmodule AtomicFiApi.KycRequirementController do
  use AtomicFiApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.KycRequirementContext
  alias AtomicFi.OpenApiSchema
  alias AtomicFi.OpenApiSchema.KycRequirementListResponse
  alias AtomicFi.OpenApiSchema.KycRequirementRequest
  alias AtomicFi.OpenApiSchema.KycRequirementResponse
  alias AtomicFiApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback AtomicFiApi.FallbackController

  tags(["KYC Requirements"])

  operation(:index,
    summary: "List KYC requirements",
    description: """
    Returns a paginated list of KYC requirements scoped to the authenticated tenant.

    Supports Flop pagination and filtering:
    - `page` - Page number (1-indexed, default: 1)
    - `page_size` - Items per page (default: 20, max: 100)
    - `order_by` - Field to sort by
    - `order_directions` - Sort direction (asc or desc)
    - `filters` - Flop filters (scope, requirement_type, status, account_holder_id, legal_entity_id)
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
        {"KYC requirement list", "application/json",
         %Reference{"$ref": "#/components/schemas/KycRequirementListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case KycRequirementContext.list_kyc_requirements(session, flop_params) do
      {:ok, {kyc_requirements, meta}} ->
        ApiHelpers.json_paginated_response(
          conn,
          kyc_requirements,
          meta,
          KycRequirementListResponse
        )

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get KYC requirement by ID",
    description: "Returns a single KYC requirement.",
    parameters: [
      id: [
        in: :path,
        description: "KYC requirement ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"KYC requirement", "application/json",
         %Reference{"$ref": "#/components/schemas/KycRequirementResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    kyc_requirement = KycRequirementContext.get_kyc_requirement!(session, id)
    ApiHelpers.json_response(conn, kyc_requirement, KycRequirementResponse)
  end

  operation(:create,
    summary: "Create KYC requirement",
    description: """
    Creates a new KYC requirement linking an AccountHolder to a LegalEntity verification action.

    The natural key is `(account_holder_id, legal_entity_id, scope, requirement_type)` — only
    one requirement per combination is allowed. Optionally provide `kyc_requirement_number` for
    an opaque external SoE ID (must be unique per tenant when present).
    """,
    request_body:
      {"KYC requirement params", "application/json", KycRequirementRequest.schema(),
       required: true},
    responses: [
      created: {"KYC requirement created", "application/json", KycRequirementResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %KycRequirementRequest{} = request} = conn, %{}) do
    session = conn.assigns.api_session

    with {:ok, kyc_requirement} <-
           KycRequirementContext.create_kyc_requirement(session, request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/kyc-requirements/#{kyc_requirement.id}")
      |> ApiHelpers.json_response(kyc_requirement, KycRequirementResponse)
    end
  end

  operation(:update,
    summary: "Update KYC requirement (full replacement)",
    description: "Updates an existing KYC requirement using PUT semantics (full replacement).",
    parameters: [
      id: [
        in: :path,
        description: "KYC requirement ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body:
      {"KYC requirement params", "application/json", KycRequirementRequest.schema(),
       required: true},
    responses: [
      ok: {"KYC requirement updated", "application/json", KycRequirementResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(%{body_params: %KycRequirementRequest{} = request} = conn, %{id: id}) do
    session = conn.assigns.api_session
    kyc_requirement = KycRequirementContext.get_kyc_requirement!(session, id)

    with {:ok, kyc_requirement} <-
           KycRequirementContext.update_kyc_requirement(session, kyc_requirement, request) do
      ApiHelpers.json_response(conn, kyc_requirement, KycRequirementResponse)
    end
  end

  operation(:delete,
    summary: "Delete KYC requirement",
    description: "Deletes a KYC requirement.",
    parameters: [
      id: [
        in: :path,
        description: "KYC requirement ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "KYC requirement deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    kyc_requirement = KycRequirementContext.get_kyc_requirement!(session, id)

    case KycRequirementContext.delete_kyc_requirement(session, kyc_requirement) do
      {:ok, _kyc_requirement} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
