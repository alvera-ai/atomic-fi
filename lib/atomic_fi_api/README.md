# AtomicFi API

REST API with OpenAPI 3.0 specification, multi-tenancy support, and comprehensive authentication.

## Directory Structure

```
lib/atomic_fi_api/
├── api_spec.ex          # OpenAPI specification
├── routes.ex            # API routes and pipelines
├── schemas.ex           # Common OpenAPI schemas
├── controllers/         # API controllers
│   └── health_controller.ex
└── schemas/             # Domain-specific OpenAPI schemas
```

## Getting Started

### 1. Enable API routes

In your `lib/atomic_fi_web/router.ex`:

```elixir
defmodule AtomicFiWeb.Router do
  use AtomicFiWeb, :router
  use AtomicFiApi.Routes  # Add this line

  # ... rest of your router
end
```

### 2. Generate resources

Use the `alvera.gen.api` task to generate API controllers:

```bash
# Generate a new API resource
mix alvera.gen.api Accounts User users email:string name:string

# Generate API for existing context
mix alvera.gen.api Accounts User users --no-context
```

### 3. View OpenAPI documentation

Start your server and visit:

- OpenAPI JSON: http://localhost:4000/api/openapi
- Health check: http://localhost:4000/api/health

Generate the OpenAPI spec file:

```bash
mix openapi.spec.yaml
# or
mix openapi.spec.json
```

## API Architecture

### Multi-Tenancy

All API endpoints are tenant-scoped. The tenant_id is extracted from the authenticated user's token and automatically applied to all queries.

```elixir
# All list functions accept tenant_id
users = Accounts.list_users(tenant_id, params)

# All get functions require tenant_id for security
user = Accounts.get_user!(id, tenant_id)
```

### Authentication

API authentication is handled via Bearer tokens in the Authorization header:

```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
     http://localhost:4000/api/v1/users
```

Implement the authentication plug in:
- `lib/atomic_fi/plugs/api_auth.ex`

### Response Format

#### Success Response

```json
{
  "data": {
    "id": "123",
    "email": "user@example.com",
    "name": "John Doe"
  }
}
```

#### List Response with Pagination

```json
{
  "data": [
    {"id": "1", "name": "Item 1"},
    {"id": "2", "name": "Item 2"}
  ],
  "meta": {
    "total": 42,
    "page": 1,
    "page_size": 10,
    "total_pages": 5
  }
}
```

#### Error Response

```json
{
  "errors": {
    "email": ["can't be blank"],
    "password": ["should be at least 8 character(s)"]
  }
}
```

## OpenAPI Schemas

OpenAPI schemas are automatically generated from your Ecto schemas when using `AtomicFi.Schema`.

Example:

```elixir
defmodule AtomicFi.Accounts.User do
  use AtomicFi.Schema

  # OpenAPI annotations
  open_api_property(schema: %Schema{type: :string, format: :email}, key: :email)
  open_api_property(schema: %Schema{type: :string}, key: :name)

  open_api_schema(
    title: "User",
    required: [:email, :owner_id],
    properties: [:id, :email, :name, :owner_id, :inserted_at, :updated_at]
  )

  typed_schema "users" do
    field :email, :string
    field :name, :string
    belongs_to :owner, AtomicFi.TenantContext.Tenant

    timestamps(type: :utc_datetime)
  end
end
```

## Testing

API tests should validate both functionality and OpenAPI compliance:

```elixir
defmodule AtomicFiApi.UserControllerTest do
  use AtomicFiWeb.ConnCase

  import OpenApiSpex.TestAssertions

  @moduletag :refactored

  test "lists users", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/users")
    response = json_response(conn, 200)

    # Validate against OpenAPI schema
    assert_schema(response, "UserListResponse", AtomicFiApi.ApiSpec.spec())
  end
end
```

## Best Practices

1. **Always scope by tenant** - Never expose data across tenant boundaries
2. **Use OpenAPI schemas** - Keep schemas in sync with implementation
3. **Version your API** - Use `/api/v1/`, `/api/v2/` etc.
4. **Return proper HTTP status codes** - 200, 201, 204, 400, 401, 403, 404, 422, 500
5. **Include pagination metadata** - For list endpoints
6. **Document thoroughly** - Use OpenAPI operation specs
7. **Test with OpenAPI validation** - Use `assert_schema/3` in tests

## Security Checklist

- [ ] Implement authentication plug
- [ ] Add rate limiting
- [ ] Enable CORS if needed
- [ ] Use HTTPS in production
- [ ] Validate all inputs
- [ ] Sanitize error messages (don't leak implementation details)
- [ ] Log API access for audit trail
- [ ] Implement API key rotation
- [ ] Monitor for unusual patterns

## Further Reading

- [OpenApiSpex Documentation](https://hexdocs.pm/open_api_spex/)
- [Phoenix API Development](https://hexdocs.pm/phoenix/json_and_apis.html)
- [REST API Best Practices](https://swagger.io/resources/articles/best-practices-in-api-design/)
