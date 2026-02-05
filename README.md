# Alvera Phoenix Template Server

A production-ready Phoenix application template for building **Industry CRMs** and **Microservices** in the Alvera ecosystem. This template combines battle-tested patterns from Hamilton Practice, Service Commerce Platform, and the main Alvera Platform.

> **Context**: In the Alvera architecture, Industry CRMs (like Hamilton Practice for healthcare, Service Commerce for consumer services) sit at the edge and integrate with the unified Data Activation and AI Platform. This template provides the foundation for building new Industry CRMs or standalone services following proven patterns.

---

## Features

- 🚀 **Phoenix 1.8+ with LiveView 1.0+** - Modern Phoenix stack with latest best practices
- 🔐 **Multi-Tenancy with RBAC** - Tenant-scoped data with role-based access control
- 🎨 **Petal Pro Components** - Pre-configured UI library with Storybook documentation
- 📊 **REST API with OpenAPI** - Documented endpoints with automatic TypeScript SDK generation
- 🧪 **Comprehensive Testing** - ExUnit, Wallaby (E2E), Vitest integration tests
- 🐳 **Docker Multi-Arch** - AMD64/ARM64 images published to GHCR
- 📝 **Audit Logging** - Console-based logging piped to S3 for forensic analysis
- 🔄 **Background Jobs** - Oban (free version) for async processing
- 🤖 **AI-Assisted Development** - Tidewave MCP for Claude Code/Cursor integration
- 📚 **ExDoc Documentation** - Comprehensive guides and API docs
- ⚙️ **GitHub Actions CI/CD** - Test, quality checks, Docker builds, integration tests

---

## Architecture Context

### Where This Template Fits

```
┌─────────────────────────────────────────────────────────────┐
│                    Alvera                           │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Industry CRMs (Built with This Template)           │    │
│  │  - Hamilton Practice (Healthcare - HIPAA)          │    │
│  │  - Service Commerce Platform (Consumer - PCI-DSS)  │    │
│  │  - Hamilton Pay (Fintech - KYC/AML)                │    │
│  │  - Future: Credit Union, Legal, Real Estate        │    │
│  └────────────────────────────────────────────────────┘    │
│                          ↕                                  │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Data Activation & AI Platform                      │    │
│  │  - Master Data Manager (MDM)                       │    │
│  │  - Data Activation (Push/Pull)                     │    │
│  │  - AI Platform (Talk to Data)                      │    │
│  │  - Agentic Workflows (Oban)                        │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

> **Salesforce Parallel**: Just as Salesforce Industry Clouds are built on Data Cloud + Agentforce, Alvera Industry CRMs are built on a unified Data Activation and AI Platform. This template provides the foundation for building those Industry CRMs.

### What This Template Includes

- ✅ **Core Phoenix patterns** from Platform project
- ✅ **Multi-tenancy & Auth** from CRM project
- ✅ **REST API with OpenAPI** from CRM project
- ✅ **Testing infrastructure** from CRM project
- ✅ **Docker & CI/CD** from CRM project
- ✅ **Petal Pro Components** from Petal Pro library
- ✅ **Storybook** from Hamilton Practice
- ✅ **Audit Logging** from Hamilton Practice

### What This Template Excludes

- ❌ Multiple datalakes (RegulatedRepo, DatalakeRepo)
- ❌ TokenizedData for PHI/PII handling
- ❌ MDM and entity resolution
- ❌ AI/ML integrations (Langchain, embeddings)
- ❌ Agentic workflows (use Platform for this)
- ❌ FHIR/healthcare-specific resources
- ❌ Oban Pro (using free Oban)

**This is a simplified starting point.** For advanced features like MDM, data activation, or agentic workflows, integrate with the main Alvera Platform.

---

## Quick Start

### 1. Clone the Template

Use this repository as a template on GitHub or clone directly:

```bash
git clone https://github.com/alvera-ai/phoenix-template-server.git my-app
cd my-app
```

### 2. Rename the Project

Use the `mix rename` task to rename from `PaymentCompliancePlatform` to your app name:

```bash
# Install dependencies first
mix deps.get

# Rename the project (updates all modules, configs, and file names)
mix rename PaymentCompliancePlatform MyApp

# This updates:
# - Module names: PaymentCompliancePlatform.* → MyApp.*
# - OTP app name in mix.exs
# - Configuration files
# - Directory names
# - File contents throughout the codebase
```

**Advanced Usage**:

```bash
# Rename with custom module prefix
mix rename PaymentCompliancePlatform MyCompany.MyApp

# Dry run to preview changes
mix rename PaymentCompliancePlatform MyApp --dry-run
```

### 3. Configure Environment

```bash
# Copy example environment file
cp .env.example .env

# Edit .env with your configuration:
# - Database credentials
# - Secret key base
# - API keys (if any)
# - Auth0/Keycloak settings (if using OAuth)
```

**Required Environment Variables**:

```bash
DATABASE_URL=ecto://postgres:postgres@localhost/myapp_dev
SECRET_KEY_BASE=generate_with_mix_phx_gen_secret
PHX_HOST=localhost
PORT=4000

# Optional: Default seeds
TENANT_NAME=my-company
ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=change_me_in_production
```

### 4. Setup Database

```bash
# Create database, run migrations, and seed
mix ecto.setup

# Or run steps individually:
mix ecto.create
mix ecto.migrate
mix run priv/repo/seeds.exs
```

### 5. Install Assets

```bash
# Install Tailwind CSS and esbuild
mix assets.setup

# Build assets
mix assets.build
```

### 6. Start the Server

```bash
# Start Phoenix server
mix phx.server

# Or start with IEx console
iex -S mix phx.server
```

**Visit**:
- **App**: http://localhost:4000
- **Storybook** (dev only): http://localhost:4000/ux-dev/storybook
- **OpenAPI Spec**: http://localhost:4000/api/openapi
- **Tidewave MCP** (dev only): http://localhost:4000/tidewave/mcp

---

## Development

### Code Generators

This template includes custom Alvera generators for scaffolding:

**Generate Context** (Ecto schema + context + tests):
```bash
mix alvera.gen.context Blog Post posts title:string content:text published_at:datetime
```

**Generate LiveView UI** (with data table):
```bash
mix alvera.gen.live Blog Post posts --data_table --route_root "/admin"
```

**Generate REST API** (with OpenAPI):
```bash
mix alvera.gen.api Blog Post posts
```

See [Generators Guide](guides/generators.md) for detailed documentation.

### Running Tests

```bash
# Run all tests
mix test

# Run with coverage
mix coveralls

# Run quality checks (format, credo, sobelow)
mix quality

# Run integration tests (TypeScript)
cd integration-tests && npm test
```

### Storybook

View and develop UI components in isolation:

```bash
mix phx.server
# Visit http://localhost:4000/ux-dev/storybook
```

**Note**: Storybook is only available in dev/test environments and requires authentication.

### AI-Assisted Development (Tidewave MCP)

This template includes Tidewave MCP for seamless AI assistant integration:

```bash
# Start Phoenix server with Tidewave enabled (dev only)
mix phx.server

# Claude Code will automatically detect the MCP server at:
# http://localhost:4000/tidewave/mcp
```

**Available AI Tools**:
- Execute Elixir code in your running application
- Query your database with SQL
- Access logs and inspect Ecto schemas
- Navigate source code and documentation
- Debug in real-time from your editor

---

## Architecture Patterns

### Multi-Tenancy

This template uses a tenant-scoped architecture following Alvera principles:

- Each **Tenant** owns **Users**, **Roles**, and data
- Row-level security via `owner_id` foreign key
- Users belong to one tenant (simplified model)
- See [Multi-Tenancy Guide](guides/multi-tenancy.md)

### Authentication

- **Local Auth**: Email/password with bcrypt
- **2FA**: TOTP-based two-factor authentication
- **OAuth** (optional): Auth0/Keycloak placeholders
- See [Authentication Guide](guides/authentication.md)

### Audit Logging

All user actions are logged to console with structured JSON (not database to avoid bloat):

- **HTTP Requests**: Via audit plug in router pipeline
- **LiveView Actions**: Via on_mount hook
- **Metadata**: current_user, current_tenant, path, params, request_id
- **Flow**: Console → Infrastructure → S3 (Parquet) → Athena for analysis

> **Why Console-Based?** Last week's debugging nightmare highlighted missing audit trails. Console logs pipe to S3 via infrastructure (CloudWatch → S3 → Glue → Athena), avoiding database bloat while enabling forensic analysis.

See [Architecture Guide](guides/architecture.md) for implementation details.

### Telemetry

Threshold-based performance monitoring:

- **Slow Queries**: Log queries > 500ms
- **Slow LiveView**: Log mounts/events > 500ms
- **Rich Metadata**: Request context for debugging

---

## Deployment

### Docker Build

```bash
# Build multi-arch image
docker build -t my-app .

# Run container
docker run -p 4000:4000 \
  -e DATABASE_URL=ecto://user:pass@host/db \
  -e SECRET_KEY_BASE=your_secret \
  my-app
```

### GitHub Actions

The template includes CI/CD workflows:

- **Test**: ExUnit tests with coverage (Codecov)
- **Code Quality**: Format, Credo, Sobelow, Dialyxir
- **Integration Tests**: Vitest with TypeScript SDK
- **Docker**: Multi-arch builds (amd64/arm64) to GHCR
- **Docs**: ExDoc generation to GitHub Pages
- **PR**: Automated PR checks with GPG commit verification

Workflows trigger on push to `main` and pull requests.

---

## Documentation

Full documentation is available via ExDoc:

```bash
# Generate docs
mix docs

# Opens in browser
```

**Available Guides**:
- [Introduction](guides/introduction.md)
- [Getting Started](guides/getting-started.md)
- [Architecture](guides/architecture.md)
- [Multi-Tenancy](guides/multi-tenancy.md)
- [Authentication](guides/authentication.md)
- [Generators](guides/generators.md)
- [Testing](guides/testing.md)
- [API Development](guides/api-development.md)
- [Deployment](guides/deployment.md)

---

## Best Practices (Learned from Production)

This template incorporates lessons learned from building Hamilton Practice (healthcare), Service Commerce Platform (consumer), and the main Alvera Platform:

### 1. **Always Run Tests Before Commit**

```bash
# Pre-commit checklist (enforced by git hooks)
mix format
mix credo --strict
mix test
```

See [CLAUDE.md](.claude/CLAUDE.md) for git conventions.

### 2. **Use Generators for Consistency**

Don't hand-write CRUD code. Use generators to ensure consistent patterns:

```bash
mix alvera.gen.context Accounts User users ...
mix alvera.gen.live Accounts User users --data_table
mix alvera.gen.api Accounts User users
```

### 3. **Log Everything to Console (Not Database)**

Audit logging goes to console → S3, never to database:

- ✅ No database bloat
- ✅ Forensic analysis via Athena
- ✅ Survives application failures

### 4. **Dual Analytics Engine Pattern**

- **Postgres**: Realtime queries (<100ms)
- **DuckDB + Parquet**: Historical/large datasets (<5s)

### 5. **Work with Raw Data Only**

Companion apps built from this template always work with raw data and interact with Alvera Platform in three ways:

1. **POST via Data Activation Client**: Push raw data to Platform using the data-activation ingest API
2. **GET via REST APIs**: Retrieve context data from Platform via REST endpoints
3. **Embedded LiveView for AI Actions**: Embed AI-powered UI components (coming later)

**Platform handles triplication** (raw/redacted/tokenized) internally for compliance. Companion apps don't need to manage this.

### 6. **Observability Sits Outside**

Monitoring should never depend on the application being monitored:
- External uptime checks (Pingdom)
- Log aggregation in separate system
- Alerts independent of main system

---

## Integration with Alvera Platform

This template can integrate with the main Alvera Platform for advanced features:

| Feature | When to Integrate |
|---------|-------------------|
| **MDM** | When you need entity resolution across multiple sources |
| **Data Activation** | When you need to pull data from external systems (EHRs, banks, APIs) |
| **AI Platform** | When you need "Talk to Data" or agentic authoring |
| **Agentic Workflows** | When you need to collect information from any party |
| **Embeddable Components** | When you want to embed AI-powered UI in your app |

**Integration Pattern**: Industry CRMs (built with this template) sync data to Platform via Database Migration Service (DMS) with CDC (Change Data Capture). Platform provides AI, MDM, and advanced workflows.

---

## Implementation Status

**Current Progress**: 5/7 core modules implemented with schemas, docs, tests, and RLS.

See [Core Modules Guide](guides/core-modules.md) for detailed status tracking of all contexts.

---

## Contributing

This template is maintained by Alvera AI. For internal use only.

When making changes:
1. Follow [Coding Guidelines](CLAUDE.md)
2. Ensure all tests pass: `mix test && mix quality`
3. Update relevant guides in `guides/`
4. Test generators work: `mix alvera.gen.*`
5. Create conventional commits with GPG signing
6. Update the Implementation Status table when completing work

---

## Version Requirements

- **Erlang**: 27.3.3
- **Elixir**: 1.18.3-otp-27
- **PostgreSQL**: 17.2
- **Node.js**: 20+ (for assets)

See `.tool-versions` for exact versions.

---

## License

Copyright © 2026 Alvera AI. All rights reserved.
