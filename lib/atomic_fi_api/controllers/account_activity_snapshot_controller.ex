defmodule AtomicFiApi.AccountActivitySnapshotController do
  use AtomicFiApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.AccountActivitySnapshotContext
  alias AtomicFi.OpenApiSchema
  alias AtomicFi.OpenApiSchema.AccountActivitySnapshotListResponse
  alias AtomicFi.OpenApiSchema.AccountActivitySnapshotRequest
  alias AtomicFi.OpenApiSchema.AccountActivitySnapshotResponse
  alias AtomicFiApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback AtomicFiApi.FallbackController

  tags(["Account Activity Snapshots"])

  operation(:index,
    summary: "List account activity snapshots",
    description: """
    Returns a paginated list of account activity snapshots scoped to the authenticated tenant.

    Supports Flop pagination and filtering:
    - `page` - Page number (1-indexed, default: 1)
    - `page_size` - Items per page (default: 20, max: 100)
    - `order_by` - Field to sort by
    - `order_directions` - Sort direction (asc or desc)
    - `filters` - Flop filters (account_holder_id, payment_account_id, ledger_account_id, snapshot_type, status, currency, flagged_for_review, period_start, period_end)
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
        example: "period_start"
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
        {"Account activity snapshot list", "application/json",
         %Reference{"$ref": "#/components/schemas/AccountActivitySnapshotListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case AccountActivitySnapshotContext.list_account_activity_snapshots(session, flop_params) do
      {:ok, {snapshots, meta}} ->
        ApiHelpers.json_paginated_response(
          conn,
          snapshots,
          meta,
          AccountActivitySnapshotListResponse
        )

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get account activity snapshot by ID",
    description: "Returns a single account activity snapshot.",
    parameters: [
      id: [
        in: :path,
        description: "Account activity snapshot ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Account activity snapshot", "application/json",
         %Reference{"$ref": "#/components/schemas/AccountActivitySnapshotResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    snapshot = AccountActivitySnapshotContext.get_account_activity_snapshot!(session, id)
    ApiHelpers.json_response(conn, snapshot, AccountActivitySnapshotResponse)
  end

  operation(:create,
    summary: "Create account activity snapshot",
    description: """
    Creates a new account activity snapshot linked to an AccountHolder.

    Maps to ISO 20022 `camt:052` (intraday) and `camt:053` (periodic statement).
    Use `snapshot_type: "intraday"` for on-demand account reports and
    `snapshot_type: "daily" | "weekly" | "monthly"` for periodic statements.

    **FinCEN AML:** Set `flagged_for_review: true` and populate `review_reason`
    when activity patterns trigger SAR thresholds (31 CFR §1020.320).
    """,
    request_body:
      {"Account activity snapshot params", "application/json",
       AccountActivitySnapshotRequest.schema(), required: true},
    responses: [
      created:
        {"Account activity snapshot created", "application/json", AccountActivitySnapshotResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(
        %{body_params: %AccountActivitySnapshotRequest{} = request} = conn,
        %{}
      ) do
    session = conn.assigns.api_session

    with {:ok, snapshot} <-
           AccountActivitySnapshotContext.create_account_activity_snapshot(session, request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/account-activity-snapshots/#{snapshot.id}")
      |> ApiHelpers.json_response(snapshot, AccountActivitySnapshotResponse)
    end
  end

  operation(:update,
    summary: "Update account activity snapshot (full replacement)",
    description:
      "Updates an existing account activity snapshot using PUT semantics (full replacement).",
    parameters: [
      id: [
        in: :path,
        description: "Account activity snapshot ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body:
      {"Account activity snapshot params", "application/json",
       AccountActivitySnapshotRequest.schema(), required: true},
    responses: [
      ok:
        {"Account activity snapshot updated", "application/json", AccountActivitySnapshotResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(
        %{body_params: %AccountActivitySnapshotRequest{} = request} = conn,
        %{id: id}
      ) do
    session = conn.assigns.api_session
    snapshot = AccountActivitySnapshotContext.get_account_activity_snapshot!(session, id)

    with {:ok, snapshot} <-
           AccountActivitySnapshotContext.update_account_activity_snapshot(
             session,
             snapshot,
             request
           ) do
      ApiHelpers.json_response(conn, snapshot, AccountActivitySnapshotResponse)
    end
  end

  operation(:delete,
    summary: "Delete account activity snapshot",
    description: "Deletes an account activity snapshot.",
    parameters: [
      id: [
        in: :path,
        description: "Account activity snapshot ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Account activity snapshot deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    snapshot = AccountActivitySnapshotContext.get_account_activity_snapshot!(session, id)

    case AccountActivitySnapshotContext.delete_account_activity_snapshot(session, snapshot) do
      {:ok, _snapshot} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
