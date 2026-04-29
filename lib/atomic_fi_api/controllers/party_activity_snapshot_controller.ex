defmodule AtomicFiApi.PartyActivitySnapshotController do
  use AtomicFiApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.OpenApiSchema
  alias AtomicFi.OpenApiSchema.PartyActivitySnapshotListResponse
  alias AtomicFi.OpenApiSchema.PartyActivitySnapshotRequest
  alias AtomicFi.OpenApiSchema.PartyActivitySnapshotResponse
  alias AtomicFi.PartyActivitySnapshotContext
  alias AtomicFiApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback AtomicFiApi.FallbackController

  tags(["Party Activity Snapshots"])

  operation(:index,
    summary: "List party activity snapshots",
    description: """
    Returns a paginated list of party activity snapshots scoped to the authenticated tenant.

    Supports Flop filtering on account_holder_id, period_type, period_start/end, sar_indicator.
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
        {"Party activity snapshot list", "application/json",
         %Reference{"$ref": "#/components/schemas/PartyActivitySnapshotListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case PartyActivitySnapshotContext.list_party_activity_snapshots(session, flop_params) do
      {:ok, {snapshots, meta}} ->
        ApiHelpers.json_paginated_response(
          conn,
          snapshots,
          meta,
          PartyActivitySnapshotListResponse
        )

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get party activity snapshot by ID",
    parameters: [
      id: [
        in: :path,
        description: "Party activity snapshot ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Party activity snapshot", "application/json",
         %Reference{"$ref": "#/components/schemas/PartyActivitySnapshotResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    snapshot = PartyActivitySnapshotContext.get_party_activity_snapshot!(session, id)
    ApiHelpers.json_response(conn, snapshot, PartyActivitySnapshotResponse)
  end

  operation(:create,
    summary: "Create party activity snapshot",
    description: """
    Creates a new party activity snapshot for an AccountHolder covering a reporting
    window. Use daily/weekly/monthly cadence for ongoing CDD (FATF Rec 10) and
    quarterly for SAR-narrative evidence (FinCEN 31 CFR §1020.320).
    """,
    request_body:
      {"Party activity snapshot params", "application/json",
       PartyActivitySnapshotRequest.schema(), required: true},
    responses: [
      created:
        {"Party activity snapshot created", "application/json", PartyActivitySnapshotResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %PartyActivitySnapshotRequest{} = request} = conn, %{}) do
    session = conn.assigns.api_session

    with {:ok, snapshot} <-
           PartyActivitySnapshotContext.create_party_activity_snapshot(session, request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/party-activity-snapshots/#{snapshot.id}")
      |> ApiHelpers.json_response(snapshot, PartyActivitySnapshotResponse)
    end
  end

  operation(:update,
    summary: "Update party activity snapshot (full replacement)",
    parameters: [
      id: [
        in: :path,
        description: "Party activity snapshot ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body:
      {"Party activity snapshot params", "application/json",
       PartyActivitySnapshotRequest.schema(), required: true},
    responses: [
      ok: {"Party activity snapshot updated", "application/json", PartyActivitySnapshotResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(%{body_params: %PartyActivitySnapshotRequest{} = request} = conn, %{id: id}) do
    session = conn.assigns.api_session
    snapshot = PartyActivitySnapshotContext.get_party_activity_snapshot!(session, id)

    with {:ok, snapshot} <-
           PartyActivitySnapshotContext.update_party_activity_snapshot(
             session,
             snapshot,
             request
           ) do
      ApiHelpers.json_response(conn, snapshot, PartyActivitySnapshotResponse)
    end
  end

  operation(:delete,
    summary: "Delete party activity snapshot",
    parameters: [
      id: [
        in: :path,
        description: "Party activity snapshot ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Party activity snapshot deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    snapshot = PartyActivitySnapshotContext.get_party_activity_snapshot!(session, id)

    case PartyActivitySnapshotContext.delete_party_activity_snapshot(session, snapshot) do
      {:ok, _snapshot} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
