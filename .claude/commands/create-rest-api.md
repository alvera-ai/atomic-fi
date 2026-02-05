# Create REST API

Generate REST API controller with OpenAPI specification.

## Usage

```bash
mix alvera.gen.api <Context> <Schema> <plural> [fields]
```

## Options

- `--no-context` - Skip context/schema generation (if already exists)
- `--no-schema` - Skip schema generation

## Example

```bash
mix alvera.gen.api Accounts User users \
  email:string \
  first_name:string \
  last_name:string
```

## Generated Files

- `lib/alvera_phoenix_template_server_api/controllers/user_controller.ex`
- `lib/alvera_phoenix_template_server_api/controllers/user_json.ex`
- `test/alvera_phoenix_template_server_api/controllers/user_controller_test.exs`
- Schema with OpenAPI annotations (if not exists)
- Context (if not exists)

## Pattern Checklist

### API Controller

```elixir
defmodule AlveraPhoenixTemplateServerApi.UserController do
  use AlveraPhoenixTemplateServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias AlveraPhoenixTemplateServer.Accounts
  alias AlveraPhoenixTemplateServer.OpenApiSchema.UserRequest
  alias AlveraPhoenixTemplateServer.OpenApiSchema.UserResponse
  alias AlveraPhoenixTemplateServer.OpenApiSchema.UserListResponse

  tags ["Users"]

  operation :index,
    summary: "List users",
    parameters: [
      page: [in: :query, type: :integer, description: "Page number"],
      page_size: [in: :query, type: :integer, description: "Items per page"]
    ],
    responses: [
      ok: {"User list", "application/json", UserListResponse}
    ]

  def index(conn, params) do
    tenant_id = conn.assigns.current_tenant_id

    with {:ok, {users, meta}} <- Accounts.list_users(tenant_id, params) do
      render(conn, :index, users: users, meta: meta)
    end
  end

  operation :show,
    summary: "Get user by ID",
    parameters: [
      id: [in: :path, type: :string, format: :uuid, description: "User ID"]
    ],
    responses: [
      ok: {"User", "application/json", UserResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]

  def show(conn, %{"id" => id}) do
    tenant_id = conn.assigns.current_tenant_id
    user = Accounts.get_user!(id, tenant_id)
    render(conn, :show, user: user)
  end

  operation :create,
    summary: "Create user",
    request_body: {"User params", "application/json", UserRequest},
    responses: [
      created: {"User created", "application/json", UserResponse},
      unprocessable_entity: {"Validation errors", "application/json", ErrorResponse}
    ]

  def create(conn, %{"user" => user_params}) do
    tenant_id = conn.assigns.current_tenant_id
    params = Map.put(user_params, "owner_id", tenant_id)

    with {:ok, user} <- Accounts.create_user(params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/users/#{user.id}")
      |> render(:show, user: user)
    end
  end

  operation :update,
    summary: "Update user",
    parameters: [
      id: [in: :path, type: :string, format: :uuid, description: "User ID"]
    ],
    request_body: {"User params", "application/json", UserRequest},
    responses: [
      ok: {"User updated", "application/json", UserResponse},
      not_found: {"Not found", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation errors", "application/json", ErrorResponse}
    ]

  def update(conn, %{"id" => id, "user" => user_params}) do
    tenant_id = conn.assigns.current_tenant_id
    user = Accounts.get_user!(id, tenant_id)

    with {:ok, user} <- Accounts.update_user(user, user_params) do
      render(conn, :show, user: user)
    end
  end

  operation :delete,
    summary: "Delete user",
    parameters: [
      id: [in: :path, type: :string, format: :uuid, description: "User ID"]
    ],
    responses: [
      no_content: "User deleted",
      not_found: {"Not found", "application/json", ErrorResponse}
    ]

  def delete(conn, %{"id" => id}) do
    tenant_id = conn.assigns.current_tenant_id
    user = Accounts.get_user!(id, tenant_id)

    with {:ok, _user} <- Accounts.delete_user(user) do
      send_resp(conn, :no_content, "")
    end
  end
end
```

### JSON View

```elixir
defmodule AlveraPhoenixTemplateServerApi.UserJSON do
  alias AlveraPhoenixTemplateServer.Accounts.User

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
      phone: user.phone,
      status: user.status,
      confirmed_at: user.confirmed_at,
      inserted_at: user.inserted_at,
      updated_at: user.updated_at
    }
  end
end
```

### Router Integration

Add API routes to `lib/alvera_phoenix_template_server_web/router.ex`:

```elixir
scope "/api", AlveraPhoenixTemplateServerApi do
  pipe_through :api

  # OpenAPI spec
  get "/openapi", OpenApiController, :spec

  # Authenticated API routes
  scope "/" do
    pipe_through :api_auth

    resources "/users", UserController, except: [:new, :edit]
  end
end
```

### Controller Tests (with OpenAPI validation)

```elixir
defmodule AlveraPhoenixTemplateServerApi.UserControllerTest do
  use AlveraPhoenixTemplateServerWeb.ConnCase, async: true

  import OpenApiSpex.TestAssertions
  import AlveraPhoenixTemplateServer.AccountsFixtures

  setup :setup_api_auth

  describe "index" do
    test "lists all users for tenant", %{conn: conn, tenant: tenant} do
      user = user_fixture(owner_id: tenant.id)

      conn = get(conn, ~p"/api/users")
      response = json_response(conn, 200)

      # Validate against OpenAPI schema
      assert_schema(response, "UserListResponse", ApiSpec.spec())

      assert length(response["data"]) == 1
      assert hd(response["data"])["id"] == user.id
    end
  end

  describe "create" do
    test "creates user with valid data", %{conn: conn} do
      attrs = %{
        email: "test@example.com",
        first_name: "John",
        last_name: "Doe"
      }

      conn = post(conn, ~p"/api/users", user: attrs)
      response = json_response(conn, 201)

      assert_schema(response, "UserResponse", ApiSpec.spec())
      assert response["data"]["email"] == "test@example.com"
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

## OpenAPI Spec Generation

After creating API endpoints:

```bash
# Generate OpenAPI spec
mix openapi.spec.yaml

# View spec at http://localhost:4000/api/openapi
```

## Key Features

- **OpenAPI 3.0**: Full spec generation with schemas
- **Request/Response Validation**: Automatic validation via OpenApiSpex
- **Multi-Tenancy**: All queries scoped by tenant_id
- **Error Handling**: Standardized error responses
- **Pagination**: Flop-powered pagination with metadata
- **Authentication**: API token or session-based auth

## Post-Generation Checklist

After successfully generating a REST API, **update the implementation status**:

1. Open [guides/core-modules.md](../../guides/core-modules.md)
2. Update the status table for this context:
   - Mark **API** as ✅ if REST endpoints are implemented and tested
   - Update the **Status** score (e.g., from 4/7 to 5/7)
3. Update the **Progress Summary** percentages for API completion
4. Ensure OpenAPI spec is generated: `mix openapi.spec.yaml`
