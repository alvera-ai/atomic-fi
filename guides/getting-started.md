# Getting Started

This guide will help you set up your development environment and get the Phoenix Template Server running.

## Prerequisites

### Required Software

- **Elixir**: 1.18.3+ (with Erlang/OTP 27.3.3+)
- **PostgreSQL**: 15+
- **Node.js**: 20+ (for assets)
- **Git**: 2.0+

### Installation

#### Using asdf (Recommended)

```bash
# Install asdf plugins
asdf plugin add elixir
asdf plugin add erlang
asdf plugin add nodejs
asdf plugin add postgres

# Install versions from .tool-versions
asdf install
```

#### Manual Installation

See official documentation:
- Elixir: https://elixir-lang.org/install.html
- PostgreSQL: https://www.postgresql.org/download/
- Node.js: https://nodejs.org/

## Project Setup

### 1. Clone or Use Template

```bash
# Use as GitHub template (recommended)
# Click "Use this template" on GitHub

# Or clone directly
git clone https://github.com/alvera-ai/phoenix-template-server.git my-app
cd my-app
```

### 2. Rename Project (Optional)

If you want to rename from `PaymentCompliancePlatform` to your app name:

```bash
# Install dependencies first
mix deps.get

# Rename project
mix rename PaymentCompliancePlatform MyApp payment_compliance_platform my_app
```

### 3. Configure Environment

```bash
# Copy example environment file
cp .env.example .env

# Edit .env with your settings
vim .env
```

**Required variables:**

```bash
# Database
DATABASE_URL=ecto://postgres:postgres@localhost/my_app_dev
TEST_DATABASE_URL=ecto://postgres:postgres@localhost/my_app_test

# Phoenix
SECRET_KEY_BASE=<generate with: mix phx.gen.secret>
PHX_HOST=localhost
PORT=4000

# Optional: Default admin user for seeds
TENANT_NAME=default-tenant
ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=changeme123!

# Optional: OAuth (if using)
# OIDC_CLIENT_ID=your_client_id
# OIDC_CLIENT_SECRET=your_client_secret
# OIDC_ISSUER=https://your-keycloak.com/realms/your-realm
```

### 4. Install Dependencies

```bash
# Fetch Elixir dependencies
mix deps.get

# Install Node.js dependencies for assets
cd assets && npm install && cd ..

# Or use the setup alias
mix setup
```

This runs:
- `mix deps.get`
- `mix ecto.setup` (create DB, run migrations, seeds)
- `mix assets.setup` (install Tailwind, esbuild)
- `mix assets.build` (compile assets)

### 5. Database Setup

```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Run seeds (creates default tenant + admin user)
mix run priv/repo/seeds.exs

# Or all at once
mix ecto.setup
```

### 6. Start the Server

```bash
# Start Phoenix server
mix phx.server

# Or with IEx console
iex -S mix phx.server
```

Visit:
- **App**: http://localhost:4000
- **LiveDashboard**: http://localhost:4000/dev/dashboard (dev only)
- **Storybook**: http://localhost:4000/ux-dev/storybook (dev only, requires auth)
- **OpenAPI Spec**: http://localhost:4000/api/openapi

## Verify Installation

### Run Tests

```bash
# Run all tests
mix test

# Run with coverage
mix coveralls

# Run specific test file
mix test test/payment_compliance_platform/accounts_test.exs
```

### Run Quality Checks

```bash
# Run all quality checks
mix quality

# Or individually
mix format --check-formatted
mix credo --strict
mix sobelow --config
```

### Compile Assets

```bash
# Build assets
mix assets.build

# Build for production
mix assets.deploy
```

## Development Workflow

### Daily Development

```bash
# Start server with live reload
mix phx.server

# In another terminal, watch tests
mix test.watch  # (if you add fswatch)

# Format code before committing
mix format

# Run quality checks
mix quality
```

### Database Changes

```bash
# Generate migration
mix ecto.gen.migration create_posts

# Run migrations
mix ecto.migrate

# Rollback last migration
mix ecto.rollback

# Reset database (drops, creates, migrates, seeds)
mix ecto.reset
```

### Code Generation

```bash
# Generate context + schema
mix alvera.gen.context Blog Post posts title:string content:text

# Generate LiveView UI
mix alvera.gen.live Blog Post posts --data_table

# Generate REST API
mix alvera.gen.api Blog Post posts
```

See [Generators Guide](generators.md) for details.

## Troubleshooting

### Port Already in Use

```bash
# Find process using port 4000
lsof -i :4000

# Kill process
kill -9 <PID>
```

### Database Connection Errors

```bash
# Verify PostgreSQL is running
psql -U postgres -c "SELECT version();"

# Check DATABASE_URL in config/dev.exs or .env
```

### Asset Compilation Errors

```bash
# Reinstall Node dependencies
cd assets
rm -rf node_modules package-lock.json
npm install
cd ..

# Rebuild assets
mix assets.build
```

### Dependency Conflicts

```bash
# Clean and reinstall
mix deps.clean --all
mix deps.get
mix deps.compile
```

## IDE Setup

### VSCode

Recommended extensions:
- ElixirLS
- Tailwind CSS IntelliSense
- Phoenix Framework

### Claude Code

Tidewave MCP is pre-configured in `.claude/settings.json`:

```json
{
  "mcpServers": {
    "tidewave": {
      "transport": "sse",
      "url": "http://localhost:4000/tidewave/mcp"
    }
  }
}
```

Start the server with `mix phx.server` and Claude Code will automatically connect.

## Next Steps

- [Architecture Guide](architecture.md) - Understand the system design
- [Multi-Tenancy Guide](multi-tenancy.md) - Learn about tenant scoping
- [Generators Guide](generators.md) - Master code generation
- [Testing Guide](testing.md) - Write effective tests

## Common Tasks

### Create New Context

```bash
mix alvera.gen.context Accounts User users email:string name:string
```

### Add LiveView UI

```bash
mix alvera.gen.live Accounts User users --data_table --route_root "/admin"
```

### Generate OpenAPI Spec

```bash
mix openapi.spec.yaml
# View at http://localhost:4000/api/openapi
```

### Run All Checks (Pre-Commit)

```bash
mix format && mix quality && mix test
```

### Deploy with Docker

```bash
docker build -t my-app .
docker run -p 4000:4000 my-app
```

See [Deployment Guide](deployment.md) for production setup.
