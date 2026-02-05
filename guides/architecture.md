# Architecture

This document describes the architecture and design patterns used in the Alvera Phoenix Template.

## System Overview

The template follows a traditional Phoenix layered architecture with multi-tenancy support:

```
┌───────────────────────────────────────────────────┐
│              Presentation Layer                    │
│  ┌─────────────────────┬─────────────────────────┐│
│  │   LiveView (HTML)   │   REST API (JSON)       ││
│  │   - Real-time UI    │   - OpenAPI 3.0         ││
│  │   - Petal Components│   - Schema validation   ││
│  │   - Storybook docs  │   - TypeScript SDK      ││
│  └─────────────────────┴─────────────────────────┘│
└───────────────────────────────────────────────────┘
                       ↓
┌───────────────────────────────────────────────────┐
│              Business Logic Layer                  │
│  ┌──────────┬──────────┬──────────┬─────────────┐│
│  │  Users   │ Tenants  │  Roles   │  [Custom]   ││
│  │ Context  │ Context  │ Context  │  Contexts   ││
│  └──────────┴──────────┴──────────┴─────────────┘│
└───────────────────────────────────────────────────┘
                       ↓
┌───────────────────────────────────────────────────┐
│               Data Access Layer                    │
│         PostgreSQL with Ecto                       │
│         Multi-Tenant (Row-Level Security)          │
└───────────────────────────────────────────────────┘
                       ↓
┌───────────────────────────────────────────────────┐
│             Infrastructure Layer                   │
│  ┌──────────┬──────────┬──────────┬─────────────┐│
│  │  Oban    │  Swoosh  │  Logger  │  Telemetry  ││
│  │  (Jobs)  │  (Email) │  (Logs)  │  (Metrics)  ││
│  └──────────┴──────────┴──────────┴─────────────┘│
└───────────────────────────────────────────────────┘
```

## Directory Structure

```
lib/
├── payment_compliance_platform/          # Business logic
│   ├── application.ex                        # OTP application
│   ├── repo.ex                              # Ecto repository
│   ├── schema.ex                            # Base schema module
│   ├── mailer.ex                            # Email mailer
│   │
│   ├── tenant_context/                      # Tenant management
│   │   ├── tenant.ex                        # Tenant schema
│   │   └── ...
│   │
│   ├── user_context/                        # User management
│   │   ├── user.ex                          # User schema
│   │   ├── user_token.ex                    # Auth tokens
│   │   ├── user_totp.ex                     # 2FA
│   │   └── ...
│   │
│   └── role_context/                        # Role management
│       ├── role.ex                          # Role schema
│       ├── scope.ex                         # Permissions
│       └── ...
│
├── payment_compliance_platform_web/      # Web interface
│   ├── endpoint.ex                          # HTTP endpoint
│   ├── router.ex                            # URL routing
│   ├── telemetry.ex                         # Metrics
│   ├── gettext.ex                           # I18n
│   │
│   ├── components/                          # UI components
│   │   ├── core_components.ex               # Phoenix defaults
│   │   ├── layouts.ex                       # Layout components
│   │   └── pro_components/                  # Petal Pro components
│   │
│   ├── controllers/                         # HTTP controllers
│   │   ├── page_controller.ex
│   │   ├── error_html.ex
│   │   └── error_json.ex
│   │
│   ├── live/                                # LiveView modules
│   │   └── hooks/                           # LiveView hooks
│   │       └── user_on_mount_hooks.ex       # Auth hooks
│   │
│   └── plugs/                               # Custom plugs
│       └── audit_logger.ex                  # Audit logging
│
└── payment_compliance_platform_api/      # REST API
    └── controllers/                         # API controllers
        └── ...
```

## Core Components

### 1. Repository (Repo)

**File**: `lib/payment_compliance_platform/repo.ex`

The Ecto repository handles all database interactions:

```elixir
defmodule PaymentCompliancePlatform.Repo do
  use Ecto.Repo,
    otp_app: :payment_compliance_platform,
    adapter: Ecto.Adapters.Postgres
end
```

**Features**:
- Connection pooling
- Transaction management
- Query building
- Changesets and validation

### 2. Schema Base Module

**File**: `lib/payment_compliance_platform/schema.ex`

Base module for all schemas with TypedEctoSchema and OpenAPI support:

```elixir
defmodule PaymentCompliancePlatform.Schema do
  defmacro __using__(_) do
    quote do
      use TypedEctoSchema
      use ExOpenApiUtils

      import Ecto.Changeset
      import Ecto.Query

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
    end
  end
end
```

### 3. Contexts

Contexts encapsulate business logic and data access:

**Pattern**:
```elixir
defmodule PaymentCompliancePlatform.UserContext do
  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.UserContext.User

  # List with tenant scoping
  def list_users(tenant_id, params \\ %{}) do
    User
    |> where(owner_id: ^tenant_id)
    |> Repo.all()
  end

  # Get with tenant scoping
  def get_user!(id, tenant_id) do
    User
    |> where(id: ^id, owner_id: ^tenant_id)
    |> Repo.one!()
  end

  # Create
  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end
end
```

### 4. Web Endpoint

**File**: `lib/payment_compliance_platform_web/endpoint.ex`

The HTTP endpoint handles all incoming requests:

```elixir
defmodule PaymentCompliancePlatformWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :payment_compliance_platform

  # WebSocket for LiveView
  socket "/live", Phoenix.LiveView.Socket

  # Tidewave MCP (dev only)
  if Code.ensure_loaded?(Tidewave) do
    plug Tidewave
  end

  # Static files, sessions, routing...
end
```

### 5. Router

**File**: `lib/payment_compliance_platform_web/router.ex`

Defines URL routing and pipelines:

```elixir
defmodule PaymentCompliancePlatformWeb.Router do
  use PaymentCompliancePlatformWeb, :router

  # Pipelines
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    # Custom plugs...
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Routes
  scope "/", PaymentCompliancePlatformWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/api", PaymentCompliancePlatformApi do
    pipe_through :api

    resources "/users", UserController
  end
end
```

## Design Patterns

### 1. Multi-Tenancy (Row-Level Security)

All tenant-scoped data includes `owner_id`:

```elixir
typed_schema "users" do
  field :email, :string
  # ... other fields ...

  # Tenant association
  belongs_to :owner, PaymentCompliancePlatform.TenantContext.Tenant

  timestamps()
end
```

**Benefits**:
- Data isolation per tenant
- Simple to reason about
- Performance via indexed queries
- No complex middleware

See [Multi-Tenancy Guide](multi-tenancy.md) for details.

### 2. Context Pattern

Contexts group related functionality:

```
UserContext/
├── user.ex              # Schema
├── user_token.ex        # Related schema
├── user_totp.ex         # Related schema
└── (context module)     # Business logic
```

**Principles**:
- Public API in context module
- Schemas are implementation details
- Test contexts, not schemas
- Keep contexts focused

### 3. OpenAPI-First APIs

API controllers use OpenApiSpex for documentation:

```elixir
operation :create,
  summary: "Create user",
  request_body: {"User params", "application/json", UserRequest},
  responses: [
    created: {"User created", "application/json", UserResponse}
  ]

def create(conn, params) do
  # Implementation...
end
```

**Benefits**:
- Auto-generated API docs
- Request/response validation
- TypeScript SDK generation
- Contract testing

### 4. LiveView Hooks

On-mount hooks for cross-cutting concerns:

```elixir
defmodule PaymentCompliancePlatformWeb.SomeLive do
  use PaymentCompliancePlatformWeb, :live_view

  on_mount {PaymentCompliancePlatformWeb.UserOnMountHooks, :require_authenticated_user}

  def mount(_params, _session, socket) do
    # current_user is available in socket.assigns
  end
end
```

**Common hooks**:
- `:require_authenticated_user` - Ensure logged in
- `:require_confirmed_user` - Ensure email confirmed
- `:attach_audit_logger` - Log user actions

## Infrastructure

### 1. Background Jobs (Oban)

**File**: `lib/payment_compliance_platform/application.ex`

```elixir
children = [
  {Oban, Application.fetch_env!(:payment_compliance_platform, Oban)}
]
```

**Job example**:
```elixir
defmodule PaymentCompliancePlatform.Workers.EmailWorker do
  use Oban.Worker, queue: :mailers

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email" => email}}) do
    # Send email...
    :ok
  end
end

# Enqueue
%{email: "user@example.com"}
|> EmailWorker.new()
|> Oban.insert()
```

### 2. Audit Logging

**File**: `lib/payment_compliance_platform_web/plugs/audit_logger.ex`

Logs every user action to console (piped to S3):

```elixir
Logger.info("audit_log",
  type: :http_request,
  path: conn.request_path,
  user_id: user_id,
  tenant_id: tenant_id,
  request_id: Logger.metadata()[:request_id]
)
```

**Flow**: Console → Infrastructure → S3 → Athena (for queries)

### 3. Telemetry

**File**: `lib/payment_compliance_platform/telemetry.ex`

Monitors slow operations:

```elixir
def handle_event([:phoenix_template, :repo, :query], measurements, metadata, _) do
  if measurements.query_time > @threshold do
    Logger.warning("slow_query", query_time: measurements.query_time)
  end
end
```

### 4. Email (Swoosh)

**File**: `lib/payment_compliance_platform/mailer.ex`

```elixir
defmodule PaymentCompliancePlatform.Mailer do
  use Swoosh.Mailer, otp_app: :payment_compliance_platform
end
```

## Security

### Authentication

- **Password**: bcrypt hashing
- **Tokens**: Secure random tokens
- **2FA**: TOTP (Time-based OTP)
- **Sessions**: Phoenix encrypted cookies

See [Authentication Guide](authentication.md).

### Authorization

- **Row-Level**: Multi-tenant via `owner_id`
- **Role-Based**: Scopes define permissions
- **Context-Level**: Functions check ownership

### API Security

- **Authentication**: Token-based or session
- **Validation**: OpenAPI schema validation
- **Rate Limiting**: (optional, add as needed)
- **CORS**: Configured in endpoint

## Testing Architecture

```
test/
├── support/
│   ├── data_case.ex          # Database tests
│   ├── conn_case.ex          # Controller tests
│   ├── factory.ex            # Test data factories
│   └── fixtures/             # Context fixtures
├── payment_compliance_platform/
│   └── *_test.exs            # Context tests
└── payment_compliance_platform_web/
    ├── controllers/
    │   └── *_controller_test.exs
    └── live/
        └── *_live_test.exs
```

See [Testing Guide](testing.md).

## Performance Considerations

### Database

- **Indexes**: All foreign keys and frequently queried fields
- **Composite Indexes**: For multi-tenant unique constraints
- **Connection Pooling**: Via Ecto (default 10)
- **Query Optimization**: Use `Repo.preload` to avoid N+1

### Caching

- **ETS**: For application-level caching
- **Agent/GenServer**: For process-level state
- **External**: Redis (optional, add as needed)

### Assets

- **Tailwind**: Minified in production
- **esbuild**: Bundled and minified
- **CDN**: (optional, configure as needed)

## Scalability

### Horizontal Scaling

- **Stateless**: No process state tied to requests
- **Database**: Single source of truth
- **Sessions**: Database-backed (scalable)
- **PubSub**: Distributed across nodes

### Vertical Scaling

- **Erlang Schedulers**: Match CPU cores
- **Database Connections**: Pool size per node
- **Memory**: Monitor with telemetry

## Development vs Production

| Feature | Development | Production |
|---------|------------|------------|
| Endpoint | `localhost:4000` | Load balanced |
| Database | Local PostgreSQL | Managed PostgreSQL |
| Assets | Live reload | Minified, CDN |
| Logging | Console | JSON to S3 |
| Storybook | Enabled | Disabled |
| Tidewave | Enabled | Disabled |

## Next Steps

- [Multi-Tenancy Guide](multi-tenancy.md) - Deep dive into tenant scoping
- [Authentication Guide](authentication.md) - Auth implementation details
- [Testing Guide](testing.md) - Testing strategies
- [Deployment Guide](deployment.md) - Production setup
