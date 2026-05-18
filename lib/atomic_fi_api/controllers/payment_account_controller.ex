defmodule AtomicFiApi.PaymentAccountController do
  use AtomicFiApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.OnboardingContext
  alias AtomicFi.OpenApiSchema
  alias AtomicFi.OpenApiSchema.PaymentAccountListResponse
  alias AtomicFi.OpenApiSchema.PaymentAccountRequest
  alias AtomicFi.OpenApiSchema.PaymentAccountResponse
  alias AtomicFi.PaymentAccountContext
  alias AtomicFiApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback AtomicFiApi.FallbackController

  tags(["Payment Accounts"])

  operation(:index,
    summary: "List payment accounts",
    description: """
    Returns a paginated list of payment accounts scoped to the authenticated tenant.

    Supports Flop pagination and filtering:
    - `page` - Page number (1-indexed, default: 1)
    - `page_size` - Items per page (default: 20, max: 100)
    - `order_by` - Field to sort by
    - `order_directions` - Sort direction (asc or desc)
    - `filters` - Flop filters (account_holder_id, legal_entity_id, counterparty_id, ledger_account_id, account_type, status, currency)
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
        {"Payment account list", "application/json",
         %Reference{"$ref": "#/components/schemas/PaymentAccountListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case PaymentAccountContext.list_payment_accounts(session, flop_params) do
      {:ok, {payment_accounts, meta}} ->
        ApiHelpers.json_paginated_response(
          conn,
          payment_accounts,
          meta,
          PaymentAccountListResponse
        )

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get payment account by ID",
    description: "Returns a single payment account.",
    parameters: [
      id: [
        in: :path,
        description: "Payment account ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Payment account", "application/json",
         %Reference{"$ref": "#/components/schemas/PaymentAccountResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    payment_account = PaymentAccountContext.get_payment_account!(session, id)
    ApiHelpers.json_response(conn, payment_account, PaymentAccountResponse)
  end

  operation(:create,
    summary: "Create payment account",
    description: """
    Creates a new payment account linked to an AccountHolder.

    Maps to ISO 20022 `pain:001 <DbtrAcct>/<CdtrAcct>`. Enables FATF
    Recommendation 16 (wire transfer rule) compliance by anchoring payments
    to a known, verified account.

    **PCI-DSS 4.0:** `account_number`, `iban`, and `card_pan` must be tokenised
    by the calling orchestration layer before writing. Never submit raw PANs.
    """,
    request_body:
      {"Payment account params", "application/json", PaymentAccountRequest.schema(),
       required: true},
    responses: [
      created: {"Payment account created", "application/json", PaymentAccountResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %PaymentAccountRequest{} = request} = conn, %{}) do
    session = conn.assigns.api_session

    with {:ok, payment_account} <-
           PaymentAccountContext.create_payment_account(session, request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/payment-accounts/#{payment_account.id}")
      |> ApiHelpers.json_response(payment_account, PaymentAccountResponse)
    end
  end

  operation(:update,
    summary: "Update payment account (full replacement)",
    description: "Updates an existing payment account using PUT semantics (full replacement).",
    parameters: [
      id: [
        in: :path,
        description: "Payment account ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body:
      {"Payment account params", "application/json", PaymentAccountRequest.schema(),
       required: true},
    responses: [
      ok: {"Payment account updated", "application/json", PaymentAccountResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(%{body_params: %PaymentAccountRequest{} = request} = conn, %{id: id}) do
    session = conn.assigns.api_session
    payment_account = PaymentAccountContext.get_payment_account!(session, id)

    with {:ok, payment_account} <-
           PaymentAccountContext.update_payment_account(session, payment_account, request) do
      ApiHelpers.json_response(conn, payment_account, PaymentAccountResponse)
    end
  end

  operation(:delete,
    summary: "Delete payment account",
    description: "Deletes a payment account.",
    parameters: [
      id: [
        in: :path,
        description: "Payment account ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Payment account deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    payment_account = PaymentAccountContext.get_payment_account!(session, id)

    case PaymentAccountContext.delete_payment_account(session, payment_account) do
      {:ok, _payment_account} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  operation(:refresh,
    summary: "Refresh payment account onboarding",
    description: """
    Manually re-runs the onboarding pipeline for an existing payment account.
    Same `OnboardingContext.refresh/2` invoked by `AtomicFi.OnboardingWorker`
    on the scheduled cadence.
    """,
    parameters: [
      id: [
        in: :path,
        description: "Payment account ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Refreshed payment account", "application/json",
         %Reference{"$ref": "#/components/schemas/PaymentAccountResponse"}},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def refresh(conn, %{id: id}) do
    session = conn.assigns.api_session
    payment_account = PaymentAccountContext.get_payment_account!(session, id)

    case OnboardingContext.refresh(session, payment_account) do
      {:ok, payment_account} ->
        ApiHelpers.json_response(conn, payment_account, PaymentAccountResponse)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
