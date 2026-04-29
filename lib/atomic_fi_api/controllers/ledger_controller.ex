defmodule AtomicFiApi.LedgerController do
  use AtomicFiApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.LedgerContext
  alias AtomicFi.OpenApiSchema
  alias AtomicFi.OpenApiSchema.LedgerListResponse
  alias AtomicFi.OpenApiSchema.LedgerRequest
  alias AtomicFi.OpenApiSchema.LedgerResponse
  alias AtomicFiApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback AtomicFiApi.FallbackController

  tags(["Ledgers"])

  operation(:index,
    summary: "List ledgers",
    description: """
    Returns a paginated list of ledgers scoped to the authenticated tenant.

    Supports Flop pagination and filtering:
    - `page` - Page number (1-indexed, default: 1)
    - `page_size` - Items per page (default: 20, max: 100)
    - `order_by` - Field to sort by
    - `order_directions` - Sort direction (asc or desc)
    - `filters` - Flop filters (account_holder_id, currency, status)
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
        {"Ledger list", "application/json",
         %Reference{"$ref": "#/components/schemas/LedgerListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case LedgerContext.list_ledgers(session, flop_params) do
      {:ok, {ledgers, meta}} ->
        ApiHelpers.json_paginated_response(conn, ledgers, meta, LedgerListResponse)

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get ledger by ID",
    description: "Returns a single ledger.",
    parameters: [
      id: [
        in: :path,
        description: "Ledger ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Ledger", "application/json", %Reference{"$ref": "#/components/schemas/LedgerResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    ledger = LedgerContext.get_ledger!(session, id)
    ApiHelpers.json_response(conn, ledger, LedgerResponse)
  end

  operation(:create,
    summary: "Create ledger",
    description: """
    Creates a new ledger for an account holder in the specified currency.

    One ledger per account_holder per currency (enforced by unique constraint).
    The currency field is authoritative for the entire ledger hierarchy.
    """,
    request_body: {"Ledger params", "application/json", LedgerRequest.schema(), required: true},
    responses: [
      created: {"Ledger created", "application/json", LedgerResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %LedgerRequest{} = ledger_request} = conn, %{}) do
    session = conn.assigns.api_session

    with {:ok, ledger} <- LedgerContext.create_ledger(session, ledger_request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/ledgers/#{ledger.id}")
      |> ApiHelpers.json_response(ledger, LedgerResponse)
    end
  end

  operation(:update,
    summary: "Update ledger (full replacement)",
    description: "Updates an existing ledger using PUT semantics (full replacement).",
    parameters: [
      id: [
        in: :path,
        description: "Ledger ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body: {"Ledger params", "application/json", LedgerRequest.schema(), required: true},
    responses: [
      ok: {"Ledger updated", "application/json", LedgerResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(%{body_params: %LedgerRequest{} = ledger_request} = conn, %{id: id}) do
    session = conn.assigns.api_session
    ledger = LedgerContext.get_ledger!(session, id)

    with {:ok, ledger} <- LedgerContext.update_ledger(session, ledger, ledger_request) do
      ApiHelpers.json_response(conn, ledger, LedgerResponse)
    end
  end

  operation(:delete,
    summary: "Delete ledger",
    description: "Deletes a ledger.",
    parameters: [
      id: [
        in: :path,
        description: "Ledger ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Ledger deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    ledger = LedgerContext.get_ledger!(session, id)

    case LedgerContext.delete_ledger(session, ledger) do
      {:ok, _ledger} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
