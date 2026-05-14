defmodule AtomicFiApi.ComplianceScreeningController do
  use AtomicFiApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.ComplianceScreeningContext
  alias AtomicFi.OpenApiSchema
  alias AtomicFi.OpenApiSchema.AccountHolderRequest
  alias AtomicFi.OpenApiSchema.BeneficialOwnerRequest
  alias AtomicFi.OpenApiSchema.ComplianceScreeningListResponse
  alias AtomicFi.OpenApiSchema.ComplianceScreeningRequest
  alias AtomicFi.OpenApiSchema.ComplianceScreeningResponse
  alias AtomicFi.OpenApiSchema.CounterpartyRequest
  alias AtomicFi.OpenApiSchema.PaymentAccountRequest
  alias AtomicFiApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback AtomicFiApi.FallbackController

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
           ComplianceScreeningContext.update_compliance_screening(session, screening, request) do
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

  # ---------------------------------------------------------------------------
  # Stateless preview screening — *Request body, single unsaved %CS{} response.
  # All in-memory entity building + engine dispatch lives in the context.
  # Onboarding handles the persisted path via the entity create/update endpoints.
  # ---------------------------------------------------------------------------

  @screening_responses [
    ok:
      {"Unsaved ComplianceScreening (preview result)", "application/json",
       %Reference{"$ref": "#/components/schemas/ComplianceScreeningResponse"}},
    unprocessable_entity:
      {"Validation errors", "application/json",
       %Reference{"$ref": "#/components/schemas/ChangesetErrors"}},
    service_unavailable:
      {"Watchman service unavailable", "application/json",
       %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
  ]

  operation(:screen_account_holder,
    summary: "Preview-screen an account holder (stateless)",
    description:
      "Stateless preview screen of an `AccountHolderRequest` (with inline " <>
        "`legal_entity`). No DB writes. Returns an unsaved `ComplianceScreeningResponse`.",
    request_body:
      {"Account holder request", "application/json", AccountHolderRequest.schema(),
       required: true},
    responses: @screening_responses
  )

  def screen_account_holder(
        %{body_params: %AccountHolderRequest{} = request} = conn,
        _params
      ) do
    case ComplianceScreeningContext.screen_account_holder(conn.assigns.api_session, request) do
      {:ok, screening} -> json(conn, ExOpenApiUtils.Mapper.to_map(screening))
      {:error, reason} -> screening_error(conn, reason)
    end
  end

  operation(:screen_beneficial_owner,
    summary: "Preview-screen a beneficial owner (stateless)",
    description:
      "Stateless preview screen of a `BeneficialOwnerRequest` (with inline " <>
        "`legal_entity`). No DB writes.",
    request_body:
      {"Beneficial owner request", "application/json", BeneficialOwnerRequest.schema(),
       required: true},
    responses: @screening_responses
  )

  def screen_beneficial_owner(
        %{body_params: %BeneficialOwnerRequest{} = request} = conn,
        _params
      ) do
    case ComplianceScreeningContext.screen_beneficial_owner(conn.assigns.api_session, request) do
      {:ok, screening} -> json(conn, ExOpenApiUtils.Mapper.to_map(screening))
      {:error, reason} -> screening_error(conn, reason)
    end
  end

  operation(:screen_counterparty,
    summary: "Preview-screen a counterparty (stateless)",
    description:
      "Stateless preview screen of a `CounterpartyRequest` (with inline " <>
        "`legal_entity`). No DB writes.",
    request_body:
      {"Counterparty request", "application/json", CounterpartyRequest.schema(), required: true},
    responses: @screening_responses
  )

  def screen_counterparty(
        %{body_params: %CounterpartyRequest{} = request} = conn,
        _params
      ) do
    case ComplianceScreeningContext.screen_counterparty(conn.assigns.api_session, request) do
      {:ok, screening} -> json(conn, ExOpenApiUtils.Mapper.to_map(screening))
      {:error, reason} -> screening_error(conn, reason)
    end
  end

  operation(:screen_payment_account,
    summary: "Preview-screen a payment account (stateless)",
    description:
      "OFAC SDN Digital Currency Address screening for crypto wallets " <>
        "(`account_type: crypto_wallet` + `wallet_address` + `wallet_chain`). " <>
        "Non-crypto rails return a no-screen `pending` result. Stateless.",
    request_body:
      {"Payment account request", "application/json", PaymentAccountRequest.schema(),
       required: true},
    responses: @screening_responses
  )

  def screen_payment_account(
        %{body_params: %PaymentAccountRequest{} = request} = conn,
        _params
      ) do
    case ComplianceScreeningContext.screen_payment_account(conn.assigns.api_session, request) do
      {:ok, screening} -> json(conn, ExOpenApiUtils.Mapper.to_map(screening))
      {:error, reason} -> screening_error(conn, reason)
    end
  end

  defp screening_error(conn, :watchman_listinfo_unavailable),
    do: watchman_unavailable(conn, "Unable to retrieve sanctions list information")

  defp screening_error(conn, :watchman_search_unavailable),
    do: watchman_unavailable(conn, "Unable to perform sanctions screening")

  defp screening_error(_conn, %Ecto.Changeset{} = changeset), do: {:error, changeset}

  defp watchman_unavailable(conn, detail) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{error: "Watchman service unavailable", detail: detail})
  end
end
