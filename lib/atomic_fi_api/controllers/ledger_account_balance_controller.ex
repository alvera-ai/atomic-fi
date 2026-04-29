defmodule AtomicFiApi.LedgerAccountBalanceController do
  use AtomicFiApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.LedgerAccountBalanceContext
  alias AtomicFi.OpenApiSchema.LedgerAccountBalanceListResponse
  alias AtomicFi.OpenApiSchema.LedgerAccountBalanceResponse
  alias AtomicFiApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback AtomicFiApi.FallbackController

  tags(["Ledger Account Balances"])

  operation(:index,
    summary: "List ledger account balances",
    description: """
    Returns a paginated list of daily balance snapshots scoped to the authenticated tenant.

    Balance rows are created and updated entirely by the `ledger_entry_propagate_to_balances`
    PostgreSQL trigger — never by application code directly.

    Each row carries day/week/month/year cumulative totals and the last known velocity limits
    propagated from the risk engine via the triggering ledger_entry's *_limit_at_entry snapshot.

    Supports Flop pagination and filtering:
    - `page` - Page number (1-indexed, default: 1)
    - `page_size` - Items per page (default: 20, max: 100)
    - `order_by` - Field to sort by (balance_date, inserted_at, updated_at)
    - `order_directions` - Sort direction (asc or desc)
    - `filters` - Flop filters (ledger_account_id, balance_date, iso_week, month, year)
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
        example: "balance_date"
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
        {"Ledger account balance list", "application/json",
         %Reference{"$ref": "#/components/schemas/LedgerAccountBalanceListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case LedgerAccountBalanceContext.list_ledger_account_balances(session, flop_params) do
      {:ok, {balances, meta}} ->
        ApiHelpers.json_paginated_response(conn, balances, meta, LedgerAccountBalanceListResponse)

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get ledger account balance by ID",
    description: """
    Returns a single daily balance snapshot. The snapshot is trigger-maintained and
    carries day/week/month/year cumulative totals and the last known velocity limits
    from the risk engine.
    """,
    parameters: [
      id: [
        in: :path,
        description: "Ledger account balance ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Ledger account balance", "application/json",
         %Reference{"$ref": "#/components/schemas/LedgerAccountBalanceResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    balance = LedgerAccountBalanceContext.get_ledger_account_balance!(session, id)
    ApiHelpers.json_response(conn, balance, LedgerAccountBalanceResponse)
  end
end
