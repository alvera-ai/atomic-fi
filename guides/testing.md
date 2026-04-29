# Testing Guide

This guide covers testing strategies and best practices for the Payments Compliance Platform.

## Overview

The template uses a comprehensive testing approach:

- **ExUnit**: Elixir's built-in test framework
- **Wallaby**: End-to-end browser testing
- **Vitest**: Integration tests for REST APIs
- **ExCoveralls**: Code coverage tracking
- **Mimic**: Mocking external dependencies

## Test Structure

```
test/
├── support/
│   ├── data_case.ex          # Database tests
│   ├── conn_case.ex          # Controller/plug tests
│   ├── channel_case.ex       # Channel tests
│   ├── factory.ex            # ExMachina factories
│   └── fixtures/             # Context fixtures
│       ├── accounts_fixtures.ex
│       └── ...
│
├── atomic_fi/
│   ├── user_context_test.exs
│   ├── tenant_context_test.exs
│   └── ...
│
├── atomic_fi_web/
│   ├── controllers/
│   │   └── user_controller_test.exs
│   ├── live/
│   │   └── user_live_test.exs
│   └── plugs/
│       └── audit_logger_test.exs
│
└── test_helper.exs
```

## Test Cases

### DataCase (Context Tests)

**File**: `test/support/data_case.ex`

```elixir
defmodule AtomicFi.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias AtomicFi.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import AtomicFi.DataCase
      import AtomicFi.Factory
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(AtomicFi.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
```

### ConnCase (Controller Tests)

**File**: `test/support/conn_case.ex`

```elixir
defmodule AtomicFiWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import AtomicFiWeb.ConnCase
      import AtomicFi.Factory

      alias AtomicFiWeb.Router.Helpers, as: Routes

      @endpoint AtomicFiWeb.Endpoint
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(AtomicFi.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def register_and_log_in_user(%{conn: conn}) do
    user = AtomicFi.Factory.insert(:user)
    %{conn: log_in_user(conn, user), user: user}
  end

  def log_in_user(conn, user) do
    token = AtomicFi.UserContext.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
```

## Factory Pattern (ExMachina)

**File**: `test/support/factory.ex`

```elixir
defmodule AtomicFi.Factory do
  use ExMachina.Ecto, repo: AtomicFi.Repo

  def tenant_factory do
    %AtomicFi.TenantContext.Tenant{
      name: sequence(:name, &"Tenant #{&1}"),
      slug: sequence(:slug, &"tenant-#{&1}"),
      status: "active"
    }
  end

  def user_factory do
    tenant = insert(:tenant)

    %AtomicFi.UserContext.User{
      email: sequence(:email, &"user#{&1}@example.com"),
      hashed_password: Bcrypt.hash_pwd_salt("password123!"),
      confirmed_at: ~U[2024-01-01 00:00:00Z],
      status: "active",
      owner: tenant
    }
  end

  def role_factory do
    tenant = insert(:tenant)

    %AtomicFi.RoleContext.Role{
      name: sequence(:role_name, &"Role #{&1}"),
      description: "Test role",
      owner: tenant
    }
  end
end
```

## Testing Contexts

### Basic Context Tests

```elixir
defmodule AtomicFi.UserContextTest do
  use AtomicFi.DataCase, async: true

  @moduletag :refactored  # For coverage tracking

  alias AtomicFi.UserContext

  describe "list_users/2" do
    test "returns all users for a tenant" do
      tenant = insert(:tenant)
      user1 = insert(:user, owner: tenant)
      user2 = insert(:user, owner: tenant)
      _other_tenant_user = insert(:user)

      users = UserContext.list_users(tenant.id)

      assert length(users) == 2
      assert user1.id in Enum.map(users, & &1.id)
      assert user2.id in Enum.map(users, & &1.id)
    end

    test "returns empty list when no users exist" do
      tenant = insert(:tenant)
      assert UserContext.list_users(tenant.id) == []
    end
  end

  describe "get_user!/2" do
    test "returns user when ID and tenant match" do
      user = insert(:user)
      assert UserContext.get_user!(user.id, user.owner_id).id == user.id
    end

    test "raises when user doesn't exist" do
      tenant = insert(:tenant)

      assert_raise Ecto.NoResultsError, fn ->
        UserContext.get_user!(Ecto.UUID.generate(), tenant.id)
      end
    end

    test "raises when tenant doesn't match" do
      user = insert(:user)
      other_tenant = insert(:tenant)

      assert_raise Ecto.NoResultsError, fn ->
        UserContext.get_user!(user.id, other_tenant.id)
      end
    end
  end

  describe "create_user/1" do
    test "creates user with valid attrs" do
      tenant = insert(:tenant)

      attrs = %{
        email: "test@example.com",
        password: "securepassword123!",
        owner_id: tenant.id
      }

      assert {:ok, user} = UserContext.create_user(attrs)
      assert user.email == "test@example.com"
      assert user.owner_id == tenant.id
    end

    test "returns error with invalid email" do
      attrs = %{email: "invalid", password: "password123!"}

      assert {:error, changeset} = UserContext.create_user(attrs)
      assert "must have the @ sign" in errors_on(changeset).email
    end

    test "returns error with short password" do
      tenant = insert(:tenant)

      attrs = %{
        email: "test@example.com",
        password: "short",
        owner_id: tenant.id
      }

      assert {:error, changeset} = UserContext.create_user(attrs)
      assert "should be at least 12 character(s)" in errors_on(changeset).password
    end
  end
end
```

### Testing with Associations

```elixir
describe "user with roles" do
  test "preloads roles correctly" do
    user = insert(:user)
    role1 = insert(:role, owner_id: user.owner_id)
    role2 = insert(:role, owner_id: user.owner_id)

    insert(:user_role, user: user, role: role1)
    insert(:user_role, user: user, role: role2)

    user = UserContext.get_user_with_roles(user.id, user.owner_id)

    assert length(user.roles) == 2
  end
end
```

## Testing Controllers

### HTTP Controller Tests

```elixir
defmodule AtomicFiApi.UserControllerTest do
  use AtomicFiWeb.ConnCase, async: true

  import OpenApiSpex.TestAssertions

  setup :register_and_log_in_user

  describe "index" do
    test "lists all users for tenant", %{conn: conn, user: user} do
      other_user = insert(:user, owner_id: user.owner_id)

      conn = get(conn, ~p"/api/users")
      response = json_response(conn, 200)

      # Validate against OpenAPI schema
      assert_schema(response, "UserListResponse", ApiSpec.spec())

      assert length(response["data"]) == 2
    end

    test "does not include users from other tenants", %{conn: conn} do
      _other_tenant_user = insert(:user)

      conn = get(conn, ~p"/api/users")
      response = json_response(conn, 200)

      assert length(response["data"]) == 1
    end
  end

  describe "create" do
    test "creates user with valid data", %{conn: conn} do
      attrs = %{email: "new@example.com", password: "password123!"}

      conn = post(conn, ~p"/api/users", user: attrs)
      response = json_response(conn, 201)

      assert_schema(response, "UserResponse", ApiSpec.spec())
      assert response["data"]["email"] == "new@example.com"
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

## Testing LiveView

### Basic LiveView Tests

```elixir
defmodule AtomicFiWeb.UserLiveTest do
  use AtomicFiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "Index" do
    test "lists all users", %{conn: conn, user: user} do
      {:ok, _index_live, html} = live(conn, ~p"/admin/users")

      assert html =~ "Users"
      assert html =~ user.email
    end

    test "saves new user", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/admin/users")

      assert index_live |> element("a", "New User") |> render_click() =~ "New User"
      assert_patch(index_live, ~p"/admin/users/new")

      assert index_live
             |> form("#user-form", user: %{email: "invalid"})
             |> render_change() =~ "must have the @ sign"

      assert index_live
             |> form("#user-form", user: %{email: "new@example.com", password: "password123!"})
             |> render_submit()

      assert_patch(index_live, ~p"/admin/users")

      html = render(index_live)
      assert html =~ "User created successfully"
      assert html =~ "new@example.com"
    end

    test "deletes user", %{conn: conn} do
      user = insert(:user, owner_id: conn.assigns.current_user.owner_id)

      {:ok, index_live, _html} = live(conn, ~p"/admin/users")

      assert index_live |> element("#users-#{user.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#users-#{user.id}")
    end
  end
end
```

### Testing LiveView Hooks

```elixir
describe "authentication" do
  test "redirects unauthenticated user", %{conn: conn} do
    conn = conn |> log_out_user()

    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/admin/users")
  end

  test "allows authenticated user", %{conn: conn} do
    assert {:ok, _view, _html} = live(conn, ~p"/admin/users")
  end
end
```

## End-to-End Testing (Wallaby)

### Setup

**File**: `test/support/feature_case.ex`

```elixir
defmodule AtomicFiWeb.FeatureCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.Feature

      import AtomicFi.Factory
      import AtomicFiWeb.FeatureCase
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AtomicFi.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(AtomicFi.Repo, {:shared, self()})
    end

    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(AtomicFi.Repo, self())
    {:ok, session} = Wallaby.start_session(metadata: metadata)
    {:ok, session: session}
  end
end
```

### E2E Tests

```elixir
defmodule AtomicFiWeb.UserRegistrationTest do
  use AtomicFiWeb.FeatureCase, async: true

  feature "user can register", %{session: session} do
    session
    |> visit("/register")
    |> fill_in(text_field("Email"), with: "test@example.com")
    |> fill_in(text_field("Password"), with: "securepassword123!")
    |> click(button("Create account"))
    |> assert_has(css(".alert-info", text: "Confirmation email sent"))
  end

  feature "registration fails with invalid email", %{session: session} do
    session
    |> visit("/register")
    |> fill_in(text_field("Email"), with: "invalid")
    |> fill_in(text_field("Password"), with: "password123!")
    |> click(button("Create account"))
    |> assert_has(css(".error", text: "must have the @ sign"))
  end
end
```

## Mocking with Mimic

### Setup

**File**: `test/test_helper.exs`

```elixir
Mimic.copy(AtomicFi.Mailer)
Mimic.copy(HTTPoison)  # For external API calls

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(AtomicFi.Repo, :manual)
```

### Mocking in Tests

```elixir
defmodule AtomicFi.UserContextTest do
  use AtomicFi.DataCase, async: false

  import Mimic

  setup :verify_on_exit!

  describe "register_user/1" do
    test "sends confirmation email" do
      # Mock mailer
      expect(AtomicFi.Mailer, :deliver, fn email ->
        assert email.to == [{"", "test@example.com"}]
        {:ok, email}
      end)

      attrs = %{email: "test@example.com", password: "password123!"}
      assert {:ok, _user} = UserContext.register_user(attrs)
    end
  end
end
```

## Integration Tests (Vitest)

### Setup

**File**: `integration-tests/vitest.config.ts`

```typescript
import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    setupFiles: ['./tests/setup.ts'],
  },
})
```

### API Integration Tests

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

  it('lists users', async () => {
    const response = await client.get('/api/users', authToken)

    expect(response.status).toBe(200)
    expect(response.data.data).toBeInstanceOf(Array)
  })

  it('creates user', async () => {
    const userData = {
      email: 'newuser@example.com',
      password: 'password123!',
    }

    const response = await client.post('/api/users', userData, authToken)

    expect(response.status).toBe(201)
    expect(response.data.data.email).toBe('newuser@example.com')
  })
})
```

## Coverage

### Running Coverage

```bash
# HTML coverage report
mix coveralls.html

# Console output
mix coveralls

# CI mode (fails if below threshold)
mix coveralls --min-coverage 80
```

### Coverage Goals

- **Refactored contexts**: 95%+ (tagged with `@moduletag :refactored`)
- **Overall project**: 80%+
- **Critical paths**: 100% (authentication, multi-tenancy)

## Best Practices

### 1. Use Async Tests

```elixir
# Most tests can run async
use AtomicFi.DataCase, async: true

# Only use async: false when:
# - Using Mimic
# - Modifying global state
# - Testing async processes
```

### 2. Test Multi-Tenancy

```elixir
test "cannot access other tenant's data" do
  user1 = insert(:user)
  user2 = insert(:user)  # Different tenant

  assert_raise Ecto.NoResultsError, fn ->
    UserContext.get_user!(user1.id, user2.owner_id)
  end
end
```

### 3. Test Edge Cases

```elixir
test "handles empty list" do
  assert UserContext.list_users(tenant.id) == []
end

test "handles nil values" do
  assert {:error, changeset} = UserContext.create_user(%{email: nil})
end
```

### 4. Use Descriptive Test Names

```elixir
# Good
test "creates user with valid email and password"
test "returns error when email is already taken for same tenant"

# Bad
test "test user creation"
test "test validation"
```

## Running Tests

```bash
# Run all tests
mix test

# Run specific file
mix test test/atomic_fi/user_context_test.exs

# Run specific line
mix test test/atomic_fi/user_context_test.exs:42

# Run with coverage
mix coveralls

# Run only refactored tests
mix test --only refactored

# Run integration tests
cd integration-tests && npm test
```

## Next Steps

- [API Development](api-development.md) - API testing patterns
- [Deployment](deployment.md) - Testing in CI/CD
- [Architecture](architecture.md) - Testing architecture
