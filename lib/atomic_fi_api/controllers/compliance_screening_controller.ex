defmodule AtomicFiApi.ComplianceScreeningController do
  use AtomicFiApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.ComplianceScreeningContext
  alias AtomicFi.OpenApiSchema
  alias AtomicFi.OpenApiSchema.ComplianceScreeningListResponse
  alias AtomicFi.OpenApiSchema.ComplianceScreeningRequest
  alias AtomicFi.OpenApiSchema.ComplianceScreeningResponse
  alias AtomicFiApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback AtomicFiApi.FallbackController

  tags(["Compliance Screening"])

  operation(:index,
    summary: "List compliance screenings",
    description: """
    Returns a paginated list of compliance screenings scoped to the authenticated tenant.

    Supports Flop pagination and filtering:
    - `page` - Page number (1-indexed, default: 1)
    - `page_size` - Items per page (default: 20, max: 100)
    - `order_by` - Field to sort by
    - `order_directions` - Sort direction (asc or desc)
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
        {"Compliance screening list", "application/json",
         %Reference{"$ref": "#/components/schemas/ComplianceScreeningListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case ComplianceScreeningContext.list_compliance_screenings(session, flop_params) do
      {:ok, {screenings, meta}} ->
        ApiHelpers.json_paginated_response(
          conn,
          screenings,
          meta,
          ComplianceScreeningListResponse
        )

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get compliance screening by ID",
    description: "Returns a single compliance screening.",
    parameters: [
      id: [
        in: :path,
        description: "Compliance screening ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Compliance screening", "application/json",
         %Reference{"$ref": "#/components/schemas/ComplianceScreeningResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    screening = ComplianceScreeningContext.get_compliance_screening!(session, id)
    ApiHelpers.json_response(conn, screening, ComplianceScreeningResponse)
  end

  operation(:update,
    summary: "Update compliance screening (review workflow)",
    description:
      "Updates a compliance screening — used for the false positive review workflow " <>
        "(e.g., setting false_positive_qualifier, review_notes, reviewed_by_user_id).",
    parameters: [
      id: [
        in: :path,
        description: "Compliance screening ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body:
      {"Compliance screening params", "application/json", ComplianceScreeningRequest.schema(),
       required: true},
    responses: [
      ok: {"Compliance screening updated", "application/json", ComplianceScreeningResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(
        %{body_params: %ComplianceScreeningRequest{} = request} = conn,
        %{id: id}
      ) do
    session = conn.assigns.api_session
    screening = ComplianceScreeningContext.get_compliance_screening!(session, id)

    with {:ok, screening} <-
           ComplianceScreeningContext.update_compliance_screening(session, screening, request) do
      ApiHelpers.json_response(conn, screening, ComplianceScreeningResponse)
    end
  end

  operation(:delete,
    summary: "Delete compliance screening",
    description: "Deletes a compliance screening.",
    parameters: [
      id: [
        in: :path,
        description: "Compliance screening ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Compliance screening deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    screening = ComplianceScreeningContext.get_compliance_screening!(session, id)

    case ComplianceScreeningContext.delete_compliance_screening(session, screening) do
      {:ok, _screening} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # Inline schema for the screen_* request bodies (entity ID only).
  @account_holder_screen_request %Schema{
    title: "AccountHolderScreenRequest",
    type: :object,
    required: [:account_holder_id],
    properties: %{
      account_holder_id: %Schema{
        type: :string,
        format: :uuid,
        description: "ID of the AccountHolder to screen"
      }
    },
    example: %{"account_holder_id" => "550e8400-e29b-41d4-a716-446655440000"}
  }

  @beneficial_owner_screen_request %Schema{
    title: "BeneficialOwnerScreenRequest",
    type: :object,
    required: [:account_holder_id, :beneficial_owner_id],
    properties: %{
      account_holder_id: %Schema{
        type: :string,
        format: :uuid,
        description: "ID of the owning AccountHolder"
      },
      beneficial_owner_id: %Schema{
        type: :string,
        format: :uuid,
        description: "ID of the BeneficialOwner to screen"
      }
    },
    example: %{
      "account_holder_id" => "550e8400-e29b-41d4-a716-446655440000",
      "beneficial_owner_id" => "660e8400-e29b-41d4-a716-446655440001"
    }
  }

  @counterparty_screen_request %Schema{
    title: "CounterpartyScreenRequest",
    type: :object,
    required: [:account_holder_id, :counterparty_id],
    properties: %{
      account_holder_id: %Schema{
        type: :string,
        format: :uuid,
        description: "ID of the internal AccountHolder"
      },
      counterparty_id: %Schema{
        type: :string,
        format: :uuid,
        description: "ID of the Counterparty to screen"
      }
    },
    example: %{
      "account_holder_id" => "550e8400-e29b-41d4-a716-446655440000",
      "counterparty_id" => "770e8400-e29b-41d4-a716-446655440002"
    }
  }

  operation(:screen_account_holder,
    summary: "Screen account holder for compliance (ISO 20022 auth:018)",
    description: """
    Loads the AccountHolder and its linked LegalEntity from the database and screens
    that entity against:
    - Internal blocklist (fail-fast, checked before Watchman)
    - Watchman OFAC/SDN/EU/UN sanctions lists

    Returns one ComplianceScreening record. Previously-reviewed false positives
    (manual_override) are automatically suppressed on re-screening.
    """,
    request_body:
      {"Account holder to screen", "application/json", @account_holder_screen_request,
       required: true},
    responses: [
      ok: {
        "Compliance screenings created",
        "application/json",
        %Schema{
          type: :array,
          items: %Reference{"$ref": "#/components/schemas/ComplianceScreeningResponse"}
        }
      },
      unprocessable_entity:
        {"Validation errors", "application/json",
         %Reference{"$ref": "#/components/schemas/ChangesetErrors"}},
      service_unavailable:
        {"Watchman service unavailable", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def screen_account_holder(conn, _params) do
    session = conn.assigns.api_session

    case ComplianceScreeningContext.screen_account_holder(session, conn.body_params) do
      {:ok, screenings} ->
        conn
        |> put_status(:ok)
        |> json(Enum.map(screenings, &ExOpenApiUtils.Mapper.to_map/1))

      {:error, :watchman_listinfo_unavailable} ->
        watchman_unavailable(conn, "Unable to retrieve sanctions list information")

      {:error, :watchman_search_unavailable} ->
        watchman_unavailable(conn, "Unable to perform sanctions screening")

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  operation(:screen_beneficial_owner,
    summary: "Screen beneficial owner for compliance (FinCEN CDD Rule)",
    description: """
    Loads the BeneficialOwner and its linked LegalEntity from the database and screens
    that entity against the internal blocklist and Watchman sanctions lists under the
    account_holder scope (beneficial owners are part of account holder CDD per FinCEN
    CDD Rule 31 CFR §1010.230).
    """,
    request_body:
      {"Beneficial owner to screen", "application/json", @beneficial_owner_screen_request,
       required: true},
    responses: [
      ok: {
        "Compliance screenings created",
        "application/json",
        %Schema{
          type: :array,
          items: %Reference{"$ref": "#/components/schemas/ComplianceScreeningResponse"}
        }
      },
      unprocessable_entity:
        {"Validation errors", "application/json",
         %Reference{"$ref": "#/components/schemas/ChangesetErrors"}},
      service_unavailable:
        {"Watchman service unavailable", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def screen_beneficial_owner(conn, _params) do
    session = conn.assigns.api_session

    case ComplianceScreeningContext.screen_beneficial_owner(session, conn.body_params) do
      {:ok, screenings} ->
        conn
        |> put_status(:ok)
        |> json(Enum.map(screenings, &ExOpenApiUtils.Mapper.to_map/1))

      {:error, :watchman_listinfo_unavailable} ->
        watchman_unavailable(conn, "Unable to retrieve sanctions list information")

      {:error, :watchman_search_unavailable} ->
        watchman_unavailable(conn, "Unable to perform sanctions screening")

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  operation(:screen_counterparty,
    summary: "Screen counterparty for compliance (ISO 20022 <Dbtr>/<Cdtr>)",
    description: """
    Loads the Counterparty and its linked LegalEntity from the database and screens
    that entity against the internal blocklist and Watchman sanctions lists under
    the counterparty scope.
    """,
    request_body:
      {"Counterparty to screen", "application/json", @counterparty_screen_request, required: true},
    responses: [
      ok: {
        "Compliance screenings created",
        "application/json",
        %Schema{
          type: :array,
          items: %Reference{"$ref": "#/components/schemas/ComplianceScreeningResponse"}
        }
      },
      unprocessable_entity:
        {"Validation errors", "application/json",
         %Reference{"$ref": "#/components/schemas/ChangesetErrors"}},
      service_unavailable:
        {"Watchman service unavailable", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def screen_counterparty(conn, _params) do
    session = conn.assigns.api_session

    case ComplianceScreeningContext.screen_counterparty(session, conn.body_params) do
      {:ok, screenings} ->
        conn
        |> put_status(:ok)
        |> json(Enum.map(screenings, &ExOpenApiUtils.Mapper.to_map/1))

      {:error, :watchman_listinfo_unavailable} ->
        watchman_unavailable(conn, "Unable to retrieve sanctions list information")

      {:error, :watchman_search_unavailable} ->
        watchman_unavailable(conn, "Unable to perform sanctions screening")

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  defp watchman_unavailable(conn, detail) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{error: "Watchman service unavailable", detail: detail})
  end
end
