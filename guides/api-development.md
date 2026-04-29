# API Development

This guide covers developing REST APIs with OpenAPI in the Payments Compliance Platform.

## Overview

The template uses OpenApiSpex for API documentation and validation:

- **OpenAPI 3.0**: Industry-standard API specification
- **Automatic Documentation**: Generated from code annotations
- **Request Validation**: Schema-based validation
- **Response Validation**: Ensure contracts are met
- **TypeScript SDK**: Auto-generated client

## Quick Start

### 1. Generate API

```bash
# Generate API controller
mix alvera.gen.api Accounts User users \
  email:string \
  first_name:string \
  last_name:string
```

### 2. Add Routes

```elixir
# lib/atomic_fi_web/router.ex
scope "/api", AtomicFiApi do
  pipe_through :api

  # OpenAPI spec endpoint
  get "/openapi", OpenApiController, :spec

  scope "/" do
    pipe_through :api_auth  # Authentication required

    resources "/users", UserController, except: [:new, :edit]
  end
end
```

### 3. Generate Spec

```bash
mix openapi.spec.yaml
```

### 4. View Docs

Visit: http://localhost:4000/api/openapi

## API Structure

### Controller

**File**: `lib/atomic_fi_api/controllers/user_controller.ex`

```elixir
defmodule AtomicFiApi.UserController do
  use AtomicFiWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.UserContext
  alias AtomicFi.OpenApiSchema.UserRequest
  alias AtomicFi.OpenApiSchema.UserResponse
  alias AtomicFi.OpenApiSchema.UserListResponse

  tags ["Users"]

  operation :index,
    summary: "List users",
    parameters: [
      page: [in: :query, type: :integer, description: "Page number", example: 1],
      page_size: [in: :query, type: :integer, description: "Items per page", example: 20]
    ],
    responses: [
      ok: {"User list", "application/json", UserListResponse},
      unauthorized: {"Unauthorized", "application/json", ErrorResponse}
    ]

  def index(conn, params) do
    tenant_id = conn.assigns.current_user.owner_id

    with {:ok, {users, meta}} <- UserContext.list_users(tenant_id, params) do
      render(conn, :index, users: users, meta: meta)
    end
  end

  operation :show,
    summary: "Get user by ID",
    parameters: [
      id: [in: :path, type: :string, format: :uuid, description: "User ID"]
    ],
    responses: [
      ok: {"User details", "application/json", UserResponse},
      not_found: {"User not found", "application/json", ErrorResponse},
      unauthorized: {"Unauthorized", "application/json", ErrorResponse}
    ]

  def show(conn, %{"id" => id}) do
    tenant_id = conn.assigns.current_user.owner_id
    user = UserContext.get_user!(id, tenant_id)
    render(conn, :show, user: user)
  end

  operation :create,
    summary: "Create a new user",
    request_body: {"User attributes", "application/json", UserRequest, required: true},
    responses: [
      created: {"User created", "application/json", UserResponse},
      unprocessable_entity: {"Validation errors", "application/json", ErrorResponse},
      unauthorized: {"Unauthorized", "application/json", ErrorResponse}
    ]

  def create(conn, %{"user" => user_params}) do
    tenant_id = conn.assigns.current_user.owner_id
    params = Map.put(user_params, "owner_id", tenant_id)

    with {:ok, user} <- UserContext.create_user(params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/users/#{user.id}")
      |> render(:show, user: user)
    end
  end

  operation :update,
    summary: "Update a user",
    parameters: [
      id: [in: :path, type: :string, format: :uuid, description: "User ID"]
    ],
    request_body: {"User attributes", "application/json", UserRequest, required: true},
    responses: [
      ok: {"User updated", "application/json", UserResponse},
      not_found: {"User not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation errors", "application/json", ErrorResponse}
    ]

  def update(conn, %{"id" => id, "user" => user_params}) do
    tenant_id = conn.assigns.current_user.owner_id
    user = UserContext.get_user!(id, tenant_id)

    with {:ok, user} <- UserContext.update_user(user, user_params) do
      render(conn, :show, user: user)
    end
  end

  operation :delete,
    summary: "Delete a user",
    parameters: [
      id: [in: :path, type: :string, format: :uuid, description: "User ID"]
    ],
    responses: [
      no_content: "User deleted successfully",
      not_found: {"User not found", "application/json", ErrorResponse}
    ]

  def delete(conn, %{"id" => id}) do
    tenant_id = conn.assigns.current_user.owner_id
    user = UserContext.get_user!(id, tenant_id)

    with {:ok, _user} <- UserContext.delete_user(user) do
      send_resp(conn, :no_content, "")
    end
  end
end
```

### JSON View

**File**: `lib/atomic_fi_api/controllers/user_json.ex`

```elixir
defmodule AtomicFiApi.UserJSON do
  alias AtomicFi.UserContext.User

  def index(%{users: users, meta: meta}) do
    %{
      data: Enum.map(users, &data/1),
      meta: %{
        total: meta.total_count,
        page: meta.page,
        page_size: meta.page_size,
        total_pages: meta.total_pages
      }
    }
  end

  def show(%{user: user}) do
    %{data: data(user)}
  end

  defp data(%User{} = user) do
    %{
      id: user.id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      status: user.status,
      confirmed_at: user.confirmed_at,
      inserted_at: user.inserted_at,
      updated_at: user.updated_at
    }
  end
end
```

## OpenAPI Schemas

### Schema Definition

**File**: `lib/atomic_fi/user_context/user.ex`

```elixir
defmodule AtomicFi.UserContext.User do
  use AtomicFi.Schema

  # OpenAPI property definitions
  open_api_property(
    schema: %Schema{type: :string, format: :uuid},
    key: :id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :email},
    key: :email
  )

  open_api_property(
    schema: %Schema{type: :string},
    key: :first_name
  )

  open_api_property(
    schema: %Schema{type: :string},
    key: :last_name
  )

  open_api_property(
    schema: %Schema{type: :string, enum: ["active", "suspended", "deleted"]},
    key: :status
  )

  # OpenAPI schema definition
  open_api_schema(
    title: "User",
    description: "A user in the system",
    required: [:email, :owner_id],
    properties: [:id, :email, :first_name, :last_name, :status, :confirmed_at, :inserted_at, :updated_at]
  )

  # Ecto schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  typed_schema "users" do
    field :email, :string
    field :first_name, :string
    field :last_name, :string
    field :status, :string, default: "active"
    field :confirmed_at, :utc_datetime

    belongs_to :owner, AtomicFi.TenantContext.Tenant

    timestamps(type: :utc_datetime)
  end
end
```

This automatically generates:
- `AtomicFi.OpenApiSchema.UserRequest` (for POST/PUT)
- `AtomicFi.OpenApiSchema.UserResponse` (for GET)

### Custom Schemas

**File**: `lib/atomic_fi/open_api_schemas.ex`

```elixir
defmodule AtomicFi.OpenApiSchemas do
  require OpenApiSpex
  alias OpenApiSpex.Schema

  defmodule UserListResponse do
    OpenApiSpex.schema(%{
      title: "UserListResponse",
      description: "Paginated list of users",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: AtomicFi.OpenApiSchema.UserResponse},
        meta: %Schema{
          type: :object,
          properties: %{
            total: %Schema{type: :integer},
            page: %Schema{type: :integer},
            page_size: %Schema{type: :integer},
            total_pages: %Schema{type: :integer}
          }
        }
      },
      required: [:data, :meta]
    })
  end

  defmodule ErrorResponse do
    OpenApiSpex.schema(%{
      title: "ErrorResponse",
      description: "Error response",
      type: :object,
      properties: %{
        errors: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :array, items: %Schema{type: :string}}
        }
      },
      required: [:errors]
    })
  end
end
```

## API Specification

### OpenAPI Controller

**File**: `lib/atomic_fi_api/controllers/open_api_controller.ex`

```elixir
defmodule AtomicFiApi.OpenApiController do
  use AtomicFiWeb, :controller

  alias AtomicFiApi.ApiSpec

  def spec(conn, _params) do
    json(conn, OpenApiSpex.OpenApi.json_encoder().encode!(ApiSpec.spec()))
  end
end
```

### API Spec Module

**File**: `lib/atomic_fi_api/api_spec.ex`

```elixir
defmodule AtomicFiApi.ApiSpec do
  alias OpenApiSpex.{Info, OpenApi, Paths, Server}
  alias AtomicFiWeb.{Endpoint, Router}

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [
        Server.from_endpoint(Endpoint)
      ],
      info: %Info{
        title: "Payments Compliance Platform API",
        version: "1.0.0",
        description: "REST API for Payments Compliance Platform",
        contact: %{
          name: "Alvera AI",
          url: "https://alvera.ai"
        }
      },
      paths: Paths.from_router(Router),
      components: %{
        securitySchemes: %{
          "bearerAuth" => %{
            "type" => "http",
            "scheme" => "bearer",
            "bearerFormat" => "JWT"
          }
        }
      },
      security: [
        %{"bearerAuth" => []}
      ]
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
```

## Authentication

### API Token

```elixir
# Generate API token for user
def generate_api_token(user) do
  token = :crypto.strong_rand_bytes(32) |> Base.url_encode64()

  {:ok, user_token} =
    %UserToken{}
    |> UserToken.changeset(%{
      user_id: user.id,
      token: token,
      context: "api-token"
    })
    |> Repo.insert()

  token
end
```

### Auth Plug

```elixir
defmodule AtomicFiWeb.ApiAuth do
  import Plug.Conn

  def api_auth(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- UserContext.get_user_by_api_token(token) do
      conn
      |> assign(:current_user, user)
      |> assign(:current_tenant_id, user.owner_id)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Unauthorized"})
        |> halt()
    end
  end
end
```

## Testing APIs

### Controller Tests

```elixir
defmodule AtomicFiApi.UserControllerTest do
  use AtomicFiWeb.ConnCase, async: true

  import OpenApiSpex.TestAssertions

  setup :setup_api_auth

  describe "GET /api/users" do
    test "returns list of users", %{conn: conn, user: user} do
      other_user = insert(:user, owner_id: user.owner_id)

      conn = get(conn, ~p"/api/users")
      response = json_response(conn, 200)

      # Validate against OpenAPI schema
      assert_schema(response, "UserListResponse", ApiSpec.spec())

      assert length(response["data"]) == 2
    end

    test "supports pagination", %{conn: conn} do
      conn = get(conn, ~p"/api/users?page=1&page_size=10")
      response = json_response(conn, 200)

      assert response["meta"]["page"] == 1
      assert response["meta"]["page_size"] == 10
    end
  end

  describe "POST /api/users" do
    test "creates user with valid data", %{conn: conn} do
      attrs = %{
        email: "new@example.com",
        first_name: "John",
        password: "password123!"
      }

      conn = post(conn, ~p"/api/users", user: attrs)
      response = json_response(conn, 201)

      assert_schema(response, "UserResponse", ApiSpec.spec())
      assert response["data"]["email"] == "new@example.com"
      assert response["data"]["first_name"] == "John"
    end

    test "returns errors with invalid data", %{conn: conn} do
      conn = post(conn, ~p"/api/users", user: %{})
      response = json_response(conn, 422)

      assert_schema(response, "ErrorResponse", ApiSpec.spec())
      assert response["errors"]["email"]
    end
  end
end
```

### Integration Tests (Vitest)

**File**: `integration-tests/tests/users.test.ts`

```typescript
import { describe, it, expect, beforeAll } from 'vitest'
import { ApiClient } from './support/api-client'

describe('Users API', () => {
  let client: ApiClient
  let authToken: string

  beforeAll(async () => {
    client = new ApiClient('http://localhost:4000')
    authToken = await client.login('admin@example.com', 'password')
  })

  describe('GET /api/users', () => {
    it('lists users', async () => {
      const response = await client.get('/api/users', authToken)

      expect(response.status).toBe(200)
      expect(response.data.data).toBeInstanceOf(Array)
      expect(response.data.meta).toHaveProperty('total')
    })

    it('supports pagination', async () => {
      const response = await client.get('/api/users?page=1&page_size=10', authToken)

      expect(response.data.meta.page).toBe(1)
      expect(response.data.meta.page_size).toBe(10)
    })
  })

  describe('POST /api/users', () => {
    it('creates user', async () => {
      const userData = {
        email: 'newuser@example.com',
        first_name: 'John',
        password: 'password123!',
      }

      const response = await client.post('/api/users', { user: userData }, authToken)

      expect(response.status).toBe(201)
      expect(response.data.data.email).toBe('newuser@example.com')
    })

    it('returns validation errors', async () => {
      const response = await client.post('/api/users', { user: {} }, authToken)

      expect(response.status).toBe(422)
      expect(response.data.errors).toHaveProperty('email')
    })
  })
})
```

## TypeScript SDK Generation

### Generate Client

```bash
# Generate OpenAPI spec
mix openapi.spec.yaml

# Install generator
npm install -g openapi-typescript-codegen

# Generate TypeScript client
openapi-typescript-codegen \
  --input http://localhost:4000/api/openapi \
  --output ./sdk \
  --client fetch

# Or use in integration-tests
cd integration-tests
npx openapi-typescript-codegen \
  --input http://localhost:4000/api/openapi \
  --output ./src/generated \
  --client fetch
```

### Using Generated Client

```typescript
import { UsersService } from './generated'

// Configure base URL and auth
UsersService.baseUrl = 'http://localhost:4000/api'
UsersService.token = authToken

// Use generated methods
const users = await UsersService.getUsers({ page: 1, pageSize: 20 })
const user = await UsersService.getUser({ id: userId })

const newUser = await UsersService.createUser({
  requestBody: {
    email: 'test@example.com',
    first_name: 'John',
  },
})
```

## Error Handling

### FallbackController

**File**: `lib/atomic_fi_api/fallback_controller.ex`

```elixir
defmodule AtomicFiApi.FallbackController do
  use AtomicFiWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: AtomicFiApi.ErrorJSON)
    |> render(:changeset_errors, changeset: changeset)
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: AtomicFiApi.ErrorJSON)
    |> render(:not_found)
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: AtomicFiApi.ErrorJSON)
    |> render(:unauthorized)
  end
end
```

### ErrorJSON

```elixir
defmodule AtomicFiApi.ErrorJSON do
  def changeset_errors(%{changeset: changeset}) do
    %{
      errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
    }
  end

  def not_found(_assigns) do
    %{errors: %{detail: "Resource not found"}}
  end

  def unauthorized(_assigns) do
    %{errors: %{detail: "Unauthorized"}}
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
```

## Best Practices

### 1. Always Scope by Tenant

```elixir
def index(conn, params) do
  # Get tenant from authenticated user
  tenant_id = conn.assigns.current_user.owner_id

  users = UserContext.list_users(tenant_id, params)
  render(conn, :index, users: users)
end
```

### 2. Use OpenAPI Annotations

```elixir
operation :create,
  summary: "Create resource",
  request_body: {"Resource", "application/json", ResourceRequest},
  responses: [
    created: {"Resource created", "application/json", ResourceResponse}
  ]
```

### 3. Validate with OpenAPI in Tests

```elixir
test "creates resource", %{conn: conn} do
  conn = post(conn, ~p"/api/resources", resource: attrs)
  response = json_response(conn, 201)

  # Validate against OpenAPI schema
  assert_schema(response, "ResourceResponse", ApiSpec.spec())
end
```

### 4. Use Fallback Controller

```elixir
defmodule MyController do
  use AtomicFiWeb, :controller

  action_fallback AtomicFiApi.FallbackController

  def create(conn, params) do
    with {:ok, resource} <- create_resource(params) do
      render(conn, :show, resource: resource)
    end
  end
end
```

## Next Steps

- [Testing Guide](testing.md) - API testing strategies
- [Deployment Guide](deployment.md) - Deploying APIs
- [Authentication Guide](authentication.md) - API authentication
