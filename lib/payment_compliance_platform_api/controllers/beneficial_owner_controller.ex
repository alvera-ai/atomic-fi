defmodule PaymentCompliancePlatformApi.BeneficialOwnerController do
  use PaymentCompliancePlatformApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias PaymentCompliancePlatform.BeneficialOwnerContext
  alias PaymentCompliancePlatform.OpenApiSchema
  alias PaymentCompliancePlatform.OpenApiSchema.BeneficialOwnerListResponse
  alias PaymentCompliancePlatform.OpenApiSchema.BeneficialOwnerRequest
  alias PaymentCompliancePlatform.OpenApiSchema.BeneficialOwnerResponse
  alias PaymentCompliancePlatformApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback PaymentCompliancePlatformApi.FallbackController

  tags(["Beneficial Owners"])

  operation(:index,
    summary: "List beneficial owners",
    description: """
    Returns a paginated list of beneficial owners scoped to the authenticated tenant.

    Supports Flop pagination and filtering:
    - `page` - Page number (1-indexed, default: 1)
    - `page_size` - Items per page (default: 20, max: 100)
    - `order_by` - Field to sort by
    - `order_directions` - Sort direction (asc or desc)
    - `filters` - Flop filters (account_holder_id, control_type, verification_status)
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
        {"Beneficial owner list", "application/json",
         %Reference{"$ref": "#/components/schemas/BeneficialOwnerListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case BeneficialOwnerContext.list_beneficial_owners(session, flop_params) do
      {:ok, {beneficial_owners, meta}} ->
        ApiHelpers.json_paginated_response(
          conn,
          beneficial_owners,
          meta,
          BeneficialOwnerListResponse
        )

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get beneficial owner by ID",
    description: "Returns a single beneficial owner.",
    parameters: [
      id: [
        in: :path,
        description: "Beneficial owner ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Beneficial owner", "application/json",
         %Reference{"$ref": "#/components/schemas/BeneficialOwnerResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    beneficial_owner = BeneficialOwnerContext.get_beneficial_owner!(session, id)
    ApiHelpers.json_response(conn, beneficial_owner, BeneficialOwnerResponse)
  end

  operation(:create,
    summary: "Create beneficial owner",
    description: """
    Creates a new beneficial owner linking a corporate AccountHolder to a LegalEntity.

    The `account_holder_id` must reference an existing AccountHolder in the same tenant.
    The `legal_entity_id` must reference an existing LegalEntity in the same tenant.
    Each (account_holder_id, legal_entity_id) pair must be unique.
    """,
    request_body:
      {"Beneficial owner params", "application/json", BeneficialOwnerRequest.schema(),
       required: true},
    responses: [
      created: {"Beneficial owner created", "application/json", BeneficialOwnerResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %BeneficialOwnerRequest{} = request} = conn, %{}) do
    session = conn.assigns.api_session
    attrs = ExOpenApiUtils.Mapper.to_map(request)

    with {:ok, beneficial_owner} <-
           BeneficialOwnerContext.create_beneficial_owner(session, attrs) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/beneficial-owners/#{beneficial_owner.id}")
      |> ApiHelpers.json_response(beneficial_owner, BeneficialOwnerResponse)
    end
  end

  operation(:update,
    summary: "Update beneficial owner (full replacement)",
    description: "Updates an existing beneficial owner using PUT semantics (full replacement).",
    parameters: [
      id: [
        in: :path,
        description: "Beneficial owner ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body:
      {"Beneficial owner params", "application/json", BeneficialOwnerRequest.schema(),
       required: true},
    responses: [
      ok: {"Beneficial owner updated", "application/json", BeneficialOwnerResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(%{body_params: %BeneficialOwnerRequest{} = request} = conn, %{id: id}) do
    session = conn.assigns.api_session
    attrs = ExOpenApiUtils.Mapper.to_map(request)
    beneficial_owner = BeneficialOwnerContext.get_beneficial_owner!(session, id)

    with {:ok, beneficial_owner} <-
           BeneficialOwnerContext.update_beneficial_owner(session, beneficial_owner, attrs) do
      ApiHelpers.json_response(conn, beneficial_owner, BeneficialOwnerResponse)
    end
  end

  operation(:delete,
    summary: "Delete beneficial owner",
    description: "Deletes a beneficial owner.",
    parameters: [
      id: [
        in: :path,
        description: "Beneficial owner ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Beneficial owner deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    beneficial_owner = BeneficialOwnerContext.get_beneficial_owner!(session, id)

    case BeneficialOwnerContext.delete_beneficial_owner(session, beneficial_owner) do
      {:ok, _beneficial_owner} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
