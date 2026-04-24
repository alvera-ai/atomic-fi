defmodule PaymentCompliancePlatformApi.BlocklistEntryController do
  use PaymentCompliancePlatformApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias PaymentCompliancePlatform.BlocklistContext
  alias PaymentCompliancePlatform.OpenApiSchema
  alias PaymentCompliancePlatform.OpenApiSchema.BlocklistEntryListResponse
  alias PaymentCompliancePlatform.OpenApiSchema.BlocklistEntryRequest
  alias PaymentCompliancePlatform.OpenApiSchema.BlocklistEntryResponse
  alias PaymentCompliancePlatformApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback PaymentCompliancePlatformApi.FallbackController

  tags(["Blocklist Entries"])

  operation(:index,
    summary: "List blocklist entries",
    description: """
    Returns a paginated list of blocklist entries scoped to the authenticated tenant.

    Supports Flop pagination and filtering on `scope`, `entry_type`, `active`.
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
        {"Blocklist entry list", "application/json",
         %Reference{"$ref": "#/components/schemas/BlocklistEntryListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case BlocklistContext.list_blocklist_entries(session, flop_params) do
      {:ok, {entries, meta}} ->
        ApiHelpers.json_paginated_response(conn, entries, meta, BlocklistEntryListResponse)

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get blocklist entry by ID",
    parameters: [
      id: [
        in: :path,
        description: "Blocklist entry ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Blocklist entry", "application/json",
         %Reference{"$ref": "#/components/schemas/BlocklistEntryResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    entry = BlocklistContext.get_blocklist_entry!(session, id)
    ApiHelpers.json_response(conn, entry, BlocklistEntryResponse)
  end

  operation(:create,
    summary: "Create blocklist entry",
    description: """
    Creates a new blocklist entry. The screening engine cache is refreshed automatically
    so the new entry takes effect immediately.
    """,
    request_body:
      {"Blocklist entry params", "application/json", BlocklistEntryRequest.schema(),
       required: true},
    responses: [
      created: {"Blocklist entry created", "application/json", BlocklistEntryResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %BlocklistEntryRequest{} = request} = conn, %{}) do
    session = conn.assigns.api_session

    with {:ok, entry} <- BlocklistContext.create_blocklist_entry(session, request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/blocklist-entries/#{entry.id}")
      |> ApiHelpers.json_response(entry, BlocklistEntryResponse)
    end
  end

  operation(:update,
    summary: "Update blocklist entry (full replacement)",
    parameters: [
      id: [
        in: :path,
        description: "Blocklist entry ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body:
      {"Blocklist entry params", "application/json", BlocklistEntryRequest.schema(),
       required: true},
    responses: [
      ok: {"Blocklist entry updated", "application/json", BlocklistEntryResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(%{body_params: %BlocklistEntryRequest{} = request} = conn, %{id: id}) do
    session = conn.assigns.api_session
    entry = BlocklistContext.get_blocklist_entry!(session, id)

    with {:ok, entry} <- BlocklistContext.update_blocklist_entry(session, entry, request) do
      ApiHelpers.json_response(conn, entry, BlocklistEntryResponse)
    end
  end

  operation(:delete,
    summary: "Delete blocklist entry",
    description:
      "Removes the blocklist entry and refreshes the screening engine cache immediately.",
    parameters: [
      id: [
        in: :path,
        description: "Blocklist entry ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Blocklist entry deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    entry = BlocklistContext.get_blocklist_entry!(session, id)

    case BlocklistContext.delete_blocklist_entry(session, entry) do
      {:ok, _entry} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
