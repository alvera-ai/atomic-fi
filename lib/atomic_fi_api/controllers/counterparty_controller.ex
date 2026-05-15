defmodule AtomicFiApi.CounterpartyController do
  use AtomicFiApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.CounterpartyContext
  alias AtomicFi.OnboardingContext
  alias AtomicFi.OpenApiSchema
  alias AtomicFi.OpenApiSchema.CounterpartyListResponse
  alias AtomicFi.OpenApiSchema.CounterpartyRequest
  alias AtomicFi.OpenApiSchema.CounterpartyResponse
  alias AtomicFiApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback AtomicFiApi.FallbackController

  tags(["Counterparties"])

  operation(:index,
    summary: "List counterparties",
    description: """
    Returns a paginated list of counterparties scoped to the authenticated tenant.

    Supports Flop pagination and filtering:
    - `page` - Page number (1-indexed, default: 1)
    - `page_size` - Items per page (default: 20, max: 100)
    - `order_by` - Field to sort by
    - `order_directions` - Sort direction (asc or desc)
    - `filters` - Flop filters (account_holder_id, status)
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
        {"Counterparty list", "application/json",
         %Reference{"$ref": "#/components/schemas/CounterpartyListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case CounterpartyContext.list_counterparties(session, flop_params) do
      {:ok, {counterparties, meta}} ->
        ApiHelpers.json_paginated_response(conn, counterparties, meta, CounterpartyListResponse)

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get counterparty by ID",
    description: "Returns a single counterparty.",
    parameters: [
      id: [
        in: :path,
        description: "Counterparty ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Counterparty", "application/json",
         %Reference{"$ref": "#/components/schemas/CounterpartyResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    counterparty = CounterpartyContext.get_counterparty!(session, id)
    ApiHelpers.json_response(conn, counterparty, CounterpartyResponse)
  end

  operation(:create,
    summary: "Create counterparty",
    description: """
    Creates a new counterparty linking an AccountHolder to a LegalEntity.

    The `account_holder_id` must reference an existing AccountHolder in the same tenant.
    The `legal_entity_id` must reference an existing LegalEntity in the same tenant.
    Each (account_holder_id, legal_entity_id) pair must be unique.
    """,
    request_body:
      {"Counterparty params", "application/json", CounterpartyRequest.schema(), required: true},
    responses: [
      created: {"Counterparty created", "application/json", CounterpartyResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %CounterpartyRequest{} = request} = conn, %{}) do
    session = conn.assigns.api_session

    with {:ok, counterparty} <- CounterpartyContext.create_counterparty(session, request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/counterparties/#{counterparty.id}")
      |> ApiHelpers.json_response(counterparty, CounterpartyResponse)
    end
  end

  operation(:update,
    summary: "Update counterparty (full replacement)",
    description: "Updates an existing counterparty using PUT semantics (full replacement).",
    parameters: [
      id: [
        in: :path,
        description: "Counterparty ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body:
      {"Counterparty params", "application/json", CounterpartyRequest.schema(), required: true},
    responses: [
      ok: {"Counterparty updated", "application/json", CounterpartyResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(%{body_params: %CounterpartyRequest{} = request} = conn, %{id: id}) do
    session = conn.assigns.api_session
    counterparty = CounterpartyContext.get_counterparty!(session, id)

    with {:ok, counterparty} <-
           CounterpartyContext.update_counterparty(session, counterparty, request) do
      ApiHelpers.json_response(conn, counterparty, CounterpartyResponse)
    end
  end

  operation(:delete,
    summary: "Delete counterparty",
    description: "Deletes a counterparty.",
    parameters: [
      id: [
        in: :path,
        description: "Counterparty ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Counterparty deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    counterparty = CounterpartyContext.get_counterparty!(session, id)

    case CounterpartyContext.delete_counterparty(session, counterparty) do
      {:ok, _counterparty} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  operation(:refresh,
    summary: "Refresh counterparty onboarding",
    description: """
    Manually re-runs the onboarding pipeline for an existing counterparty.
    Same `OnboardingContext.refresh/2` invoked by `AtomicFi.OnboardingWorker`
    on the scheduled cadence.
    """,
    parameters: [
      id: [
        in: :path,
        description: "Counterparty ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Refreshed counterparty", "application/json",
         %Reference{"$ref": "#/components/schemas/CounterpartyResponse"}},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def refresh(conn, %{id: id}) do
    session = conn.assigns.api_session
    counterparty = CounterpartyContext.get_counterparty!(session, id)

    case OnboardingContext.refresh(session, counterparty) do
      {:ok, counterparty} ->
        ApiHelpers.json_response(conn, counterparty, CounterpartyResponse)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
