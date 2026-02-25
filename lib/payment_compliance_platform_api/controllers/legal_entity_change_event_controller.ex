defmodule PaymentCompliancePlatformApi.LegalEntityChangeEventController do
  use PaymentCompliancePlatformApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias PaymentCompliancePlatform.LegalEntityChangeEventContext
  alias PaymentCompliancePlatform.OpenApiSchema
  alias PaymentCompliancePlatform.OpenApiSchema.LegalEntityChangeEventListResponse
  alias PaymentCompliancePlatform.OpenApiSchema.LegalEntityChangeEventRequest
  alias PaymentCompliancePlatform.OpenApiSchema.LegalEntityChangeEventResponse
  alias PaymentCompliancePlatformApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback PaymentCompliancePlatformApi.FallbackController

  tags(["Legal Entity Change Events"])

  operation(:index,
    summary: "List legal entity change events",
    description: """
    Returns a paginated list of legal entity change events scoped to the authenticated tenant.

    Change events are primarily auto-created by `update_legal_entity` and represent an
    append-only audit log of identity lifecycle changes (ISO 20022 acmt:006/acmt:002).

    Primary AML signals for account takeover detection:
    - `phone_change` — SIM swap attacks
    - `address_change` — address velocity patterns
    - `beneficiary_added` / `authorised_signer_change` — pre-transfer grooming

    Supports Flop pagination and filtering:
    - `page` - Page number (1-indexed, default: 1)
    - `page_size` - Items per page (default: 20, max: 100)
    - `order_by` - Field to sort by
    - `order_directions` - Sort direction (asc or desc)
    - `filters` - Flop filters (legal_entity_id, account_holder_id, beneficial_owner_id, event_type, change_channel, event_status)
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
        {"Legal entity change event list", "application/json",
         %Reference{"$ref": "#/components/schemas/LegalEntityChangeEventListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case LegalEntityChangeEventContext.list_legal_entity_change_events(session, flop_params) do
      {:ok, {events, meta}} ->
        ApiHelpers.json_paginated_response(
          conn,
          events,
          meta,
          LegalEntityChangeEventListResponse
        )

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get legal entity change event by ID",
    description: "Returns a single legal entity change event including JSONB diff and snapshot.",
    parameters: [
      id: [
        in: :path,
        description: "Legal entity change event ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Legal entity change event", "application/json",
         %Reference{"$ref": "#/components/schemas/LegalEntityChangeEventResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    event = LegalEntityChangeEventContext.get_legal_entity_change_event!(session, id)
    ApiHelpers.json_response(conn, event, LegalEntityChangeEventResponse)
  end

  operation(:create,
    summary: "Create legal entity change event",
    description: """
    Creates a new legal entity change event.

    Use this endpoint to record externally received acmt:006 messages or to manually
    log identity change requests. Events auto-created by `update_legal_entity` are NOT
    returned in the update response — use GET /legal-entity-change-events to retrieve them.

    Maps to ISO 20022:
    - `acmt:006` — AccountModificationInstruction (via `acmt_instruction_id`)
    - `acmt:002` — AccountDetailsConfirmation (via `acmt_confirmation_id`)
    """,
    request_body:
      {"Legal entity change event params", "application/json",
       LegalEntityChangeEventRequest.schema(), required: true},
    responses: [
      created:
        {"Legal entity change event created", "application/json", LegalEntityChangeEventResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(
        %{body_params: %LegalEntityChangeEventRequest{} = request} = conn,
        %{}
      ) do
    session = conn.assigns.api_session

    with {:ok, event} <-
           LegalEntityChangeEventContext.create_legal_entity_change_event(session, request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/legal-entity-change-events/#{event.id}")
      |> ApiHelpers.json_response(event, LegalEntityChangeEventResponse)
    end
  end

  operation(:update,
    summary: "Update legal entity change event (mutable fields only)",
    description: """
    Updates mutable fields of an existing legal entity change event.

    Only non-system fields are mutable: `event_status`, `change_channel`,
    `acmt_instruction_id`, `acmt_confirmation_id`, `account_holder_id`, `beneficial_owner_id`.

    System-generated fields (`changes`, `previous_state`, `legal_entity_id`) are immutable
    after creation and are ignored even if provided.
    """,
    parameters: [
      id: [
        in: :path,
        description: "Legal entity change event ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body:
      {"Legal entity change event params", "application/json",
       LegalEntityChangeEventRequest.schema(), required: true},
    responses: [
      ok:
        {"Legal entity change event updated", "application/json", LegalEntityChangeEventResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(
        %{body_params: %LegalEntityChangeEventRequest{} = request} = conn,
        %{id: id}
      ) do
    session = conn.assigns.api_session
    event = LegalEntityChangeEventContext.get_legal_entity_change_event!(session, id)

    with {:ok, event} <-
           LegalEntityChangeEventContext.update_legal_entity_change_event(
             session,
             event,
             request
           ) do
      ApiHelpers.json_response(conn, event, LegalEntityChangeEventResponse)
    end
  end

  operation(:delete,
    summary: "Delete legal entity change event",
    description: "Deletes a legal entity change event.",
    parameters: [
      id: [
        in: :path,
        description: "Legal entity change event ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Legal entity change event deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    event = LegalEntityChangeEventContext.get_legal_entity_change_event!(session, id)

    case LegalEntityChangeEventContext.delete_legal_entity_change_event(session, event) do
      {:ok, _event} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
