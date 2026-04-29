defmodule AtomicFiApi.CustomerController do
  use AtomicFiApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.CustomerContext
  alias AtomicFi.OpenApiSchema
  alias AtomicFi.OpenApiSchema.CustomerListResponse
  alias AtomicFi.OpenApiSchema.CustomerRequest
  alias AtomicFi.OpenApiSchema.CustomerResponse
  alias AtomicFiApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback AtomicFiApi.FallbackController

  tags(["Customers"])

  operation(:index,
    summary: "List customers",
    description: """
    Returns a paginated list of customer organisations scoped to the authenticated tenant.

    Supports Flop pagination and filtering on `name`, `slug`, `status`.
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
        {"Customer list", "application/json",
         %Reference{"$ref": "#/components/schemas/CustomerListResponse"}}
    ]
  )

  def index(conn, params) do
    session = conn.assigns.api_session
    flop_params = ApiHelpers.parse_flop_params(params)

    case CustomerContext.list_customers(session, flop_params) do
      {:ok, {customers, meta}} ->
        ApiHelpers.json_paginated_response(conn, customers, meta, CustomerListResponse)

      {:error, flop_meta} ->
        {:error, flop_meta}
    end
  end

  operation(:show,
    summary: "Get customer by ID",
    parameters: [
      id: [
        in: :path,
        description: "Customer ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok:
        {"Customer", "application/json",
         %Reference{"$ref": "#/components/schemas/CustomerResponse"}},
      not_found:
        {"Not found", "application/json",
         %Reference{"$ref": "#/components/schemas/ErrorResponse"}}
    ]
  )

  def show(conn, %{id: id}) do
    session = conn.assigns.api_session
    customer = CustomerContext.get_customer!(session, id)
    ApiHelpers.json_response(conn, customer, CustomerResponse)
  end

  operation(:create,
    summary: "Create customer",
    description: """
    Creates a new customer organisation within the authenticated tenant. Default
    customer-scoped roles (`customer_admin`, `employee`, `customer_api`) are
    seeded automatically on create.
    """,
    request_body:
      {"Customer params", "application/json", CustomerRequest.schema(), required: true},
    responses: [
      created: {"Customer created", "application/json", CustomerResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(%{body_params: %CustomerRequest{} = request} = conn, %{}) do
    session = conn.assigns.api_session

    with {:ok, customer} <- CustomerContext.create_customer(session, request) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/customers/#{customer.id}")
      |> ApiHelpers.json_response(customer, CustomerResponse)
    end
  end

  operation(:update,
    summary: "Update customer (full replacement)",
    parameters: [
      id: [
        in: :path,
        description: "Customer ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    request_body:
      {"Customer params", "application/json", CustomerRequest.schema(), required: true},
    responses: [
      ok: {"Customer updated", "application/json", CustomerResponse},
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def update(%{body_params: %CustomerRequest{} = request} = conn, %{id: id}) do
    session = conn.assigns.api_session
    customer = CustomerContext.get_customer!(session, id)

    with {:ok, customer} <- CustomerContext.update_customer(session, customer, request) do
      ApiHelpers.json_response(conn, customer, CustomerResponse)
    end
  end

  operation(:delete,
    summary: "Delete customer",
    parameters: [
      id: [
        in: :path,
        description: "Customer ID",
        schema: %Schema{type: :string, format: :uuid},
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      no_content: "Customer deleted",
      not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(conn, %{id: id}) do
    session = conn.assigns.api_session
    customer = CustomerContext.get_customer!(session, id)

    case CustomerContext.delete_customer(session, customer) do
      {:ok, _customer} ->
        send_resp(conn, :no_content, "")

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
