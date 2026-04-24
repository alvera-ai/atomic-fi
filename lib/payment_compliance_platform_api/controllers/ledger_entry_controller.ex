defmodule PaymentCompliancePlatformApi.LedgerEntryController do
  use PaymentCompliancePlatformApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias PaymentCompliancePlatform.LedgerEntryContext
  alias PaymentCompliancePlatform.OpenApiSchema
  alias PaymentCompliancePlatform.OpenApiSchema.LedgerEntryListResponse
  alias PaymentCompliancePlatform.OpenApiSchema.LedgerEntryRequest
  alias PaymentCompliancePlatform.OpenApiSchema.LedgerEntryResponse
  alias PaymentCompliancePlatformApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback PaymentCompliancePlatformApi.FallbackController

  tags(["Ledger Entries"])

  operation(:index,
    summary: "List ledger entries",
    description: """
    Returns a paginated list of ledger entries scoped to the authenticated tenant.

    Supports Flop pagination and filtering:
    - `page` - Page number (1-indexed, default: 1)
    - `page_size` - Items per page (default: 20, max: 100)
    - `order_by` - Field to sort by
    - `order_directions` - Sort direction (asc or desc)
    - `filters` - Flop filters (ledger_account_id, account_holder_id, entry_type, status)
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
        {"Ledger entry list", "application/json",
         %Reference{"$ref": "#/components/schemas/LedgerEntryListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case LedgerEntryContext.list_ledger_entries(session, flop_params) do
      {:ok, {ledger_entries, meta}} ->
        ApiHelpers.json_paginated_response(conn, ledger_entries, meta, LedgerEntryListResponse)

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get ledger entry by ID",
    description: "Returns a single ledger entry.",
    parameters: [
      id: [
        in: :path,
        description: "Ledger entry ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Ledger entry", "application/json",
         %Reference{"$ref": "#/components/schemas/LedgerEntryResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    ledger_entry = LedgerEntryContext.get_ledger_entry!(session, id)
    ApiHelpers.json_response(conn, ledger_entry, LedgerEntryResponse)
  end

  operation(:create,
    summary: "Create ledger entry",
    description: """
    Creates a new ledger entry (debit or credit line) and atomically updates the parent LedgerAccount balance.

    - `credit` entry → balance += amount
    - `debit` entry → balance -= amount (returns 422 if balance would go negative — overdraft protection)

    Currency must match the parent LedgerAccount (which inherits from the parent Ledger).
    """,
    request_body:
      {"Ledger entry params", "application/json", LedgerEntryRequest.schema(), required: true},
    responses: [
      created: {"Ledger entry created", "application/json", LedgerEntryResponse},
      unprocessable_entity:
        {"Validation errors or overdraft", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %LedgerEntryRequest{} = ledger_entry_request} = conn, %{}) do
    session = conn.assigns.api_session

    with {:ok, ledger_entry} <-
           LedgerEntryContext.create_ledger_entry(session, ledger_entry_request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/ledger-entries/#{ledger_entry.id}")
      |> ApiHelpers.json_response(ledger_entry, LedgerEntryResponse)
    end
  end

  operation(:update,
    summary: "Update ledger entry (full replacement)",
    description: """
    Updates an existing ledger entry using PUT semantics (full replacement).

    Transitioning `status` to `reversed` atomically reverses the balance delta on the parent LedgerAccount.
    Other status transitions (e.g. pending → posted) do not affect the balance.
    """,
    parameters: [
      id: [
        in: :path,
        description: "Ledger entry ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body:
      {"Ledger entry params", "application/json", LedgerEntryRequest.schema(), required: true},
    responses: [
      ok: {"Ledger entry updated", "application/json", LedgerEntryResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(
        %{body_params: %LedgerEntryRequest{} = ledger_entry_request} = conn,
        %{id: id}
      ) do
    session = conn.assigns.api_session
    ledger_entry = LedgerEntryContext.get_ledger_entry!(session, id)

    with {:ok, ledger_entry} <-
           LedgerEntryContext.update_ledger_entry(session, ledger_entry, ledger_entry_request) do
      ApiHelpers.json_response(conn, ledger_entry, LedgerEntryResponse)
    end
  end

  operation(:delete,
    summary: "Delete ledger entry",
    description: """
    Deletes a ledger entry.

    NOTE: Deleting a posted entry does NOT reverse the balance.
    To reverse a posted entry's balance effect, update its status to `reversed` first.
    """,
    parameters: [
      id: [
        in: :path,
        description: "Ledger entry ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Ledger entry deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    ledger_entry = LedgerEntryContext.get_ledger_entry!(session, id)

    case LedgerEntryContext.delete_ledger_entry(session, ledger_entry) do
      {:ok, _ledger_entry} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
