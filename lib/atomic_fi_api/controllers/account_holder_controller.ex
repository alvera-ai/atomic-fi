defmodule AtomicFiApi.AccountHolderController do
  use AtomicFiApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.AccountHolderContext
  alias AtomicFi.OnboardingContext
  alias AtomicFi.OpenApiSchema
  alias AtomicFi.OpenApiSchema.AccountHolderListResponse
  alias AtomicFi.OpenApiSchema.AccountHolderRequest
  alias AtomicFi.OpenApiSchema.AccountHolderResponse
  alias AtomicFiApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback AtomicFiApi.FallbackController

  tags(["Account Holders"])

  operation(:index,
    summary: "List account holders",
    description: """
    Returns a paginated list of account holders scoped to the authenticated tenant.

    Supports Flop pagination and filtering:
    - `page` - Page number (1-indexed, default: 1)
    - `page_size` - Items per page (default: 20, max: 100)
    - `order_by` - Field to sort by
    - `order_directions` - Sort direction (asc or desc)
    - `filters` - Flop filters (holder_type, status, kyc_status, risk_level)
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
        {"Account holder list", "application/json",
         %Reference{"$ref": "#/components/schemas/AccountHolderListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case AccountHolderContext.list_account_holders(session, flop_params) do
      {:ok, {account_holders, meta}} ->
        ApiHelpers.json_paginated_response(
          conn,
          account_holders,
          meta,
          AccountHolderListResponse
        )

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get account holder by ID",
    description: "Returns a single account holder.",
    parameters: [
      id: [
        in: :path,
        description: "Account holder ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Account holder", "application/json",
         %Reference{"$ref": "#/components/schemas/AccountHolderResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    account_holder = AccountHolderContext.get_account_holder!(session, id)
    ApiHelpers.json_response(conn, account_holder, AccountHolderResponse)
  end

  operation(:create,
    summary: "Create account holder",
    description: """
    Creates a new account holder linked to an existing legal entity.

    The `legal_entity_id` must reference an existing LegalEntity in the same tenant.
    """,
    request_body:
      {"Account holder params", "application/json", AccountHolderRequest.schema(), required: true},
    responses: [
      created: {"Account holder created", "application/json", AccountHolderResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %AccountHolderRequest{} = account_holder_request} = conn, %{}) do
    session = conn.assigns.api_session

    with {:ok, account_holder} <-
           AccountHolderContext.create_account_holder(session, account_holder_request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/account-holders/#{account_holder.id}")
      |> ApiHelpers.json_response(account_holder, AccountHolderResponse)
    end
  end

  operation(:update,
    summary: "Update account holder (full replacement)",
    description: "Updates an existing account holder using PUT semantics (full replacement).",
    parameters: [
      id: [
        in: :path,
        description: "Account holder ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body:
      {"Account holder params", "application/json", AccountHolderRequest.schema(), required: true},
    responses: [
      ok: {"Account holder updated", "application/json", AccountHolderResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(
        %{body_params: %AccountHolderRequest{} = account_holder_request} = conn,
        %{id: id}
      ) do
    session = conn.assigns.api_session
    account_holder = AccountHolderContext.get_account_holder!(session, id)

    with {:ok, account_holder} <-
           AccountHolderContext.update_account_holder(
             session,
             account_holder,
             account_holder_request
           ) do
      ApiHelpers.json_response(conn, account_holder, AccountHolderResponse)
    end
  end

  operation(:delete,
    summary: "Delete account holder",
    description: "Deletes an account holder.",
    parameters: [
      id: [
        in: :path,
        description: "Account holder ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Account holder deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    account_holder = AccountHolderContext.get_account_holder!(session, id)

    case AccountHolderContext.delete_account_holder(session, account_holder) do
      {:ok, _account_holder} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  operation(:refresh,
    summary: "Refresh account holder onboarding",
    description: """
    Manually re-runs the onboarding pipeline (screening + RuleEngine +
    control application) for an existing account holder. Clears the
    currently-scheduled rescreen job and enqueues a new one based on the
    engine's `next_screening_at`.

    Used by operator-driven re-screen flows; the same `OnboardingContext.refresh/2`
    is invoked by `AtomicFi.OnboardingWorker` on the scheduled cadence.
    """,
    parameters: [
      id: [
        in: :path,
        description: "Account holder ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Refreshed account holder", "application/json",
         %Reference{"$ref": "#/components/schemas/AccountHolderResponse"}},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def refresh(conn, %{id: id}) do
    session = conn.assigns.api_session
    account_holder = AccountHolderContext.get_account_holder!(session, id)

    case OnboardingContext.refresh(session, account_holder) do
      {:ok, account_holder} ->
        ApiHelpers.json_response(conn, account_holder, AccountHolderResponse)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
