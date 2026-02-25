defmodule PaymentCompliancePlatformApi.LedgerAccountController do
  use PaymentCompliancePlatformApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias PaymentCompliancePlatform.LedgerAccountContext
  alias PaymentCompliancePlatform.OpenApiSchema
  alias PaymentCompliancePlatform.OpenApiSchema.LedgerAccountListResponse
  alias PaymentCompliancePlatform.OpenApiSchema.LedgerAccountRequest
  alias PaymentCompliancePlatform.OpenApiSchema.LedgerAccountResponse
  alias PaymentCompliancePlatformApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback PaymentCompliancePlatformApi.FallbackController

  tags(["Ledger Accounts"])

  operation(:index,
    summary: "List ledger accounts",
    description: """
    Returns a paginated list of ledger accounts scoped to the authenticated tenant.

    Supports Flop pagination and filtering:
    - `page` - Page number (1-indexed, default: 1)
    - `page_size` - Items per page (default: 20, max: 100)
    - `order_by` - Field to sort by
    - `order_directions` - Sort direction (asc or desc)
    - `filters` - Flop filters (ledger_id, account_holder_id, account_type, status)
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
        {"Ledger account list", "application/json",
         %Reference{"$ref": "#/components/schemas/LedgerAccountListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case LedgerAccountContext.list_ledger_accounts(session, flop_params) do
      {:ok, {ledger_accounts, meta}} ->
        ApiHelpers.json_paginated_response(
          conn,
          ledger_accounts,
          meta,
          LedgerAccountListResponse
        )

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get ledger account by ID",
    description:
      "Returns a single ledger account. The `balance` field reflects the current running total in minor currency units.",
    parameters: [
      id: [
        in: :path,
        description: "Ledger account ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Ledger account", "application/json",
         %Reference{"$ref": "#/components/schemas/LedgerAccountResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    ledger_account = LedgerAccountContext.get_ledger_account!(session, id)
    ApiHelpers.json_response(conn, ledger_account, LedgerAccountResponse)
  end

  operation(:create,
    summary: "Create ledger account",
    description: """
    Creates a new ledger account within a ledger.

    One ledger account per ledger per account_type (enforced by unique constraint).
    Currency is inherited from the parent ledger — provide the matching ISO 4217 code.
    Balance starts at 0 and is maintained atomically by the Ledger Entry system.
    """,
    request_body:
      {"Ledger account params", "application/json", LedgerAccountRequest.schema(), required: true},
    responses: [
      created: {"Ledger account created", "application/json", LedgerAccountResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %LedgerAccountRequest{} = ledger_account_request} = conn, %{}) do
    session = conn.assigns.api_session

    with {:ok, ledger_account} <-
           LedgerAccountContext.create_ledger_account(session, ledger_account_request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/ledger-accounts/#{ledger_account.id}")
      |> ApiHelpers.json_response(ledger_account, LedgerAccountResponse)
    end
  end

  operation(:update,
    summary: "Update ledger account (full replacement)",
    description: """
    Updates an existing ledger account using PUT semantics (full replacement).

    NOTE: `balance` is read-only and cannot be updated through this endpoint.
    Use the Ledger Entry endpoints to create debit/credit entries that atomically update the balance.
    """,
    parameters: [
      id: [
        in: :path,
        description: "Ledger account ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body:
      {"Ledger account params", "application/json", LedgerAccountRequest.schema(), required: true},
    responses: [
      ok: {"Ledger account updated", "application/json", LedgerAccountResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(
        %{body_params: %LedgerAccountRequest{} = ledger_account_request} = conn,
        %{id: id}
      ) do
    session = conn.assigns.api_session
    ledger_account = LedgerAccountContext.get_ledger_account!(session, id)

    with {:ok, ledger_account} <-
           LedgerAccountContext.update_ledger_account(
             session,
             ledger_account,
             ledger_account_request
           ) do
      ApiHelpers.json_response(conn, ledger_account, LedgerAccountResponse)
    end
  end

  operation(:delete,
    summary: "Delete ledger account",
    description: "Deletes a ledger account.",
    parameters: [
      id: [
        in: :path,
        description: "Ledger account ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Ledger account deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    ledger_account = LedgerAccountContext.get_ledger_account!(session, id)

    case LedgerAccountContext.delete_ledger_account(session, ledger_account) do
      {:ok, _ledger_account} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
