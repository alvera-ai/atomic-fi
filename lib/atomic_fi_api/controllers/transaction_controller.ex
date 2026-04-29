defmodule AtomicFiApi.TransactionController do
  use AtomicFiApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.OpenApiSchema
  alias AtomicFi.OpenApiSchema.TransactionListResponse
  alias AtomicFi.OpenApiSchema.TransactionRequest
  alias AtomicFi.OpenApiSchema.TransactionResponse
  alias AtomicFi.TransactionContext
  alias AtomicFiApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback AtomicFiApi.FallbackController

  tags(["Transactions"])

  operation(:index,
    summary: "List transactions",
    description: """
    Returns a paginated list of transactions scoped to the authenticated tenant.

    Supports Flop pagination and filtering:
    - `page` - Page number (1-indexed, default: 1)
    - `page_size` - Items per page (default: 20, max: 100)
    - `order_by` - Field to sort by
    - `order_directions` - Sort direction (asc or desc)
    - `filters` - Flop filters (account_holder_id, debtor_payment_account_id, creditor_payment_account_id, debtor_counterparty_id, creditor_counterparty_id, transaction_type, status, currency, settlement_date)
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
        {"Transaction list", "application/json",
         %Reference{"$ref": "#/components/schemas/TransactionListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case TransactionContext.list_transactions(session, flop_params) do
      {:ok, {transactions, meta}} ->
        ApiHelpers.json_paginated_response(
          conn,
          transactions,
          meta,
          TransactionListResponse
        )

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get transaction by ID",
    description: "Returns a single transaction.",
    parameters: [
      id: [
        in: :path,
        description: "Transaction ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Transaction", "application/json",
         %Reference{"$ref": "#/components/schemas/TransactionResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    transaction = TransactionContext.get_transaction!(session, id)
    ApiHelpers.json_response(conn, transaction, TransactionResponse)
  end

  operation(:create,
    summary: "Create transaction",
    description: """
    Creates a new payment transaction linked to an AccountHolder.

    Maps to ISO 20022 `pain:001` CustomerCreditTransferInitiation.
    FATF Recommendation 16: debtor/creditor PaymentAccounts must be verified
    before settlement. The orchestration layer must enforce this check.

    **PCI-DSS 4.0:** Raw PAN data must never appear in transaction fields.
    Use tokenised card references via the linked PaymentAccount only.
    """,
    request_body:
      {"Transaction params", "application/json", TransactionRequest.schema(), required: true},
    responses: [
      created: {"Transaction created", "application/json", TransactionResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %TransactionRequest{} = request} = conn, %{}) do
    session = conn.assigns.api_session

    with {:ok, transaction} <- TransactionContext.create_transaction(session, request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/transactions/#{transaction.id}")
      |> ApiHelpers.json_response(transaction, TransactionResponse)
    end
  end

  operation(:update,
    summary: "Update transaction (full replacement)",
    description: "Updates an existing transaction using PUT semantics (full replacement).",
    parameters: [
      id: [
        in: :path,
        description: "Transaction ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body:
      {"Transaction params", "application/json", TransactionRequest.schema(), required: true},
    responses: [
      ok: {"Transaction updated", "application/json", TransactionResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(%{body_params: %TransactionRequest{} = request} = conn, %{id: id}) do
    session = conn.assigns.api_session
    transaction = TransactionContext.get_transaction!(session, id)

    with {:ok, transaction} <-
           TransactionContext.update_transaction(session, transaction, request) do
      ApiHelpers.json_response(conn, transaction, TransactionResponse)
    end
  end

  operation(:delete,
    summary: "Delete transaction",
    description: "Deletes a transaction.",
    parameters: [
      id: [
        in: :path,
        description: "Transaction ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Transaction deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    transaction = TransactionContext.get_transaction!(session, id)

    case TransactionContext.delete_transaction(session, transaction) do
      {:ok, _transaction} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
