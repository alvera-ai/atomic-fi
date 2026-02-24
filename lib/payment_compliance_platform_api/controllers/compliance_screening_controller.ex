defmodule PaymentCompliancePlatformApi.ComplianceScreeningController do
  use PaymentCompliancePlatformApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias PaymentCompliancePlatform.ComplianceScreeningContext
  alias PaymentCompliancePlatform.ComplianceScreeningContext.ScreeningRequest
  alias PaymentCompliancePlatform.OpenApiSchema
  alias PaymentCompliancePlatform.OpenApiSchema.ComplianceScreeningListResponse
  alias PaymentCompliancePlatform.OpenApiSchema.ComplianceScreeningRequest
  alias PaymentCompliancePlatform.OpenApiSchema.ComplianceScreeningResponse
  alias PaymentCompliancePlatformApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback PaymentCompliancePlatformApi.FallbackController

  tags(["Compliance Screening"])

  operation(:index,
    summary: "List compliance screenings",
    description: """
    Returns a paginated list of compliance screenings scoped to the authenticated tenant.

    Supports Flop pagination and filtering:
    - `page` - Page number (1-indexed, default: 1)
    - `page_size` - Items per page (default: 20, max: 100)
    - `order_by` - Field to sort by
    - `order_directions` - Sort direction (asc or desc)
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
        {"Compliance screening list", "application/json",
         %Reference{"$ref": "#/components/schemas/ComplianceScreeningListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case ComplianceScreeningContext.list_compliance_screenings(session, flop_params) do
      {:ok, {screenings, meta}} ->
        ApiHelpers.json_paginated_response(
          conn,
          screenings,
          meta,
          ComplianceScreeningListResponse
        )

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get compliance screening by ID",
    description: "Returns a single compliance screening.",
    parameters: [
      id: [
        in: :path,
        description: "Compliance screening ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Compliance screening", "application/json",
         %Reference{"$ref": "#/components/schemas/ComplianceScreeningResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    screening = ComplianceScreeningContext.get_compliance_screening!(session, id)
    ApiHelpers.json_response(conn, screening, ComplianceScreeningResponse)
  end

  operation(:update,
    summary: "Update compliance screening (review workflow)",
    description:
      "Updates a compliance screening — used for the false positive review workflow " <>
        "(e.g., setting false_positive_qualifier, review_notes, reviewed_by_user_id).",
    parameters: [
      id: [
        in: :path,
        description: "Compliance screening ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body:
      {"Compliance screening params", "application/json", ComplianceScreeningRequest.schema(),
       required: true},
    responses: [
      ok: {"Compliance screening updated", "application/json", ComplianceScreeningResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(
        %{body_params: %ComplianceScreeningRequest{} = request} = conn,
        %{id: id}
      ) do
    session = conn.assigns.api_session
    screening = ComplianceScreeningContext.get_compliance_screening!(session, id)

    with {:ok, screening} <-
           ComplianceScreeningContext.update_compliance_screening(
             session,
             screening,
             Map.from_struct(request)
           ) do
      ApiHelpers.json_response(conn, screening, ComplianceScreeningResponse)
    end
  end

  operation(:delete,
    summary: "Delete compliance screening",
    description: "Deletes a compliance screening.",
    parameters: [
      id: [
        in: :path,
        description: "Compliance screening ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Compliance screening deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    screening = ComplianceScreeningContext.get_compliance_screening!(session, id)

    case ComplianceScreeningContext.delete_compliance_screening(session, screening) do
      {:ok, _screening} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  operation(:screen_account_holder,
    summary: "Screen account holder for compliance (ISO 20022 auth:018)",
    description: """
    Screens an account holder and all listed individuals/companies against:
    - Internal blocklist (fail-fast, checked before Watchman)
    - Watchman OFAC/SDN/EU/UN sanctions lists

    Returns one ComplianceScreening record per entity screened. Previously-reviewed
    false positives (manual_override) are automatically suppressed on re-screening.
    """,
    request_body: {"Entities to screen", "application/json", ScreeningRequest, required: true},
    responses: [
      ok: {
        "Compliance screenings created",
        "application/json",
        %Schema{
          type: :array,
          items: %Reference{"$ref": "#/components/schemas/ComplianceScreeningResponse"}
        }
      },
      unprocessable_entity:
        {"Validation errors", "application/json",
         %Reference{"$ref": "#/components/schemas/ChangesetErrors"}},
      service_unavailable:
        {"Watchman service unavailable", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def screen_account_holder(
        %{body_params: %ScreeningRequest{} = request} = conn,
        _params
      ) do
    session = conn.assigns.api_session

    case ComplianceScreeningContext.screen_account_holder(session, request) do
      {:ok, screenings} ->
        conn
        |> put_status(:ok)
        |> json(Enum.map(screenings, &Map.from_struct/1))

      {:error, :watchman_listinfo_unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          error: "Watchman service unavailable",
          detail: "Unable to retrieve sanctions list information"
        })

      {:error, :watchman_search_unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          error: "Watchman service unavailable",
          detail: "Unable to perform sanctions screening"
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  operation(:screen_beneficial_owner,
    summary: "Screen beneficial owner for compliance (FinCEN CDD Rule)",
    description: """
    Screens a beneficial owner and all listed individuals/companies against the
    internal blocklist and Watchman sanctions lists under the account_holder scope
    (beneficial owners are part of account holder CDD per FinCEN CDD Rule 31 CFR §1010.230).
    """,
    request_body: {"Entities to screen", "application/json", ScreeningRequest, required: true},
    responses: [
      ok: {
        "Compliance screenings created",
        "application/json",
        %Schema{
          type: :array,
          items: %Reference{"$ref": "#/components/schemas/ComplianceScreeningResponse"}
        }
      },
      unprocessable_entity:
        {"Validation errors", "application/json",
         %Reference{"$ref": "#/components/schemas/ChangesetErrors"}},
      service_unavailable:
        {"Watchman service unavailable", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def screen_beneficial_owner(
        %{body_params: %ScreeningRequest{} = request} = conn,
        _params
      ) do
    session = conn.assigns.api_session

    case ComplianceScreeningContext.screen_beneficial_owner(session, request) do
      {:ok, screenings} ->
        conn
        |> put_status(:ok)
        |> json(Enum.map(screenings, &Map.from_struct/1))

      {:error, :watchman_listinfo_unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          error: "Watchman service unavailable",
          detail: "Unable to retrieve sanctions list information"
        })

      {:error, :watchman_search_unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          error: "Watchman service unavailable",
          detail: "Unable to perform sanctions screening"
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  operation(:screen_counterparty,
    summary: "Screen counterparty for compliance (ISO 20022 <Dbtr>/<Cdtr>)",
    description: """
    Screens a counterparty and all listed individuals/companies against the
    internal blocklist and Watchman sanctions lists under the counterparty scope.
    Requires both account_holder_id and counterparty_id in the request body.
    """,
    request_body: {"Entities to screen", "application/json", ScreeningRequest, required: true},
    responses: [
      ok: {
        "Compliance screenings created",
        "application/json",
        %Schema{
          type: :array,
          items: %Reference{"$ref": "#/components/schemas/ComplianceScreeningResponse"}
        }
      },
      unprocessable_entity:
        {"Validation errors", "application/json",
         %Reference{"$ref": "#/components/schemas/ChangesetErrors"}},
      service_unavailable:
        {"Watchman service unavailable", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def screen_counterparty(
        %{body_params: %ScreeningRequest{} = request} = conn,
        _params
      ) do
    session = conn.assigns.api_session

    case ComplianceScreeningContext.screen_counterparty(session, request) do
      {:ok, screenings} ->
        conn
        |> put_status(:ok)
        |> json(Enum.map(screenings, &Map.from_struct/1))

      {:error, :watchman_listinfo_unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          error: "Watchman service unavailable",
          detail: "Unable to retrieve sanctions list information"
        })

      {:error, :watchman_search_unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          error: "Watchman service unavailable",
          detail: "Unable to perform sanctions screening"
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end
end
