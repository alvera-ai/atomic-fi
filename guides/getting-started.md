# Getting Started

This guide will help you set up your development environment and get AtomicFi running locally.

> **Just want it running?** `docker compose up` builds and starts the entire
> stack (backend + all demo apps + backing services) at
> http://localhost:4100 — no local Elixir/Node toolchain required. See
> [INSTALLATION.md](../INSTALLATION.md). The rest of this guide covers the
> **native** workflow for active development.

## Prerequisites

### Required Software

- **Elixir**: 1.18.3-otp-27 / **Erlang**: 27.3.3 (see `.tool-versions`)
- **PostgreSQL**: 17.2 — managed via Docker (see below; no local install needed)
- **Docker**: for all backing services (Postgres, Watchman, ZenRule, Mockoon)
- **pnpm**: for JS example apps — `corepack enable` or `brew install pnpm`

### Recommended: asdf for Elixir/Erlang

```bash
asdf plugin add elixir
asdf plugin add erlang
asdf install  # reads .tool-versions automatically
```

### Optional: AI features

- **Ollama** — local LLM for the JDM rule editor copilot and document parser
  ```bash
  brew install ollama && ollama serve
  ollama pull llama3.2-vision:11b   # document parser (/api/parse)
  ollama pull qwen2.5:7b            # JDM copilot (/api/copilotkit)
  ```
- **poppler** — PDF rasterization for the document parser
  ```bash
  brew install poppler   # macOS
  ```

---

## Setup

### 1. Install dependencies

```bash
mix deps.get
pnpm install
```

### 2. Configure environment (optional)

Copy `.env.example` to `.env` and fill in your API key if you want cloud-model AI features. Without it, Ollama-backed defaults are used.

```bash
cp .env.example .env
```

The `.env.example` contains:

```bash
# Lotus SQL copilot
LOTUS_AI_MODEL=google:gemini-2.5-flash
LOTUS_AI_API_KEY=your-api-key-here

# JDM rule editor copilot (overrides Ollama default)
LLM_PROVIDER=google
LLM_MODEL=gemini-2.5-flash
GOOGLE_API_KEY=your-api-key-here
```

### 3. Start backing services

```bash
make run-backing-services
```

This runs `docker compose -f local-dependencies.yaml up` for:
- **Moov Watchman** (sanctions screening) on `:8084`
- **ZenRule / gorules agent** (decision rules engine) on `:8090`
- **Mockoon** (external API mock) on `:8085`
- **CopilotKit runtime** (JDM editor AI sidecar) on `:4242`
- **Vector** (CopilotKit telemetry sink) on `:8686`

> **Postgres** is *not* part of `local-dependencies.yaml`. The native flow
> expects Postgres on `localhost:5432` (`config/dev.exs`). Run one locally, or
> start just the bundled one with `docker compose up -d postgres` (from the
> full-stack `docker-compose.yml`).

### 4. Create the database and seed

```bash
mix ecto.setup   # creates DB, runs migrations
make seed        # runs mix corpus.validate --reset (populates test corpus)
```

### 5. Start the server

```bash
make server
```

This starts `iex --sname phoenix@localhost -S mix phx.server` and auto-loads `.env` if present.

**Visit:**
- **Home / demos**: http://localhost:4100/
- **API Docs (Scalar)**: http://localhost:4100/api/docs
- **OpenAPI spec**: http://localhost:4100/api/openapi

---

## One-liner (first-time or full reset)

```bash
make run
```

Equivalent to `make up` (backing services + DB setup + seed) followed by `make server`.

---

## Makefile reference

| Command | What it does |
|---|---|
| `make run-backing-services` | `docker compose up` — all backing services |
| `make stop-backing-services` | `docker compose down` |
| `make up` | backing services + `mix ecto.setup` + seed |
| `make down` | stop backing services |
| `make server` | start Phoenix with a named IEx node |
| `make console` | attach a remote IEx console to the running server |
| `make run` | `make up` then `make server` (everything) |
| `make seed` | re-seed corpus data (`mix corpus.validate --reset`) |
| `make deps.logs` | follow Docker Compose logs |
| `make deps.status` | show running Docker Compose services |

---

## Verify installation

### Run tests

```bash
mix test
```

### Run quality checks

```bash
mix format --check-formatted
mix credo --strict
```

### Verify Watchman (sanctions screening)

```bash
curl -s "http://localhost:8084/v2/search?name=Nicolas+Maduro&type=person&limit=3"
```

---

## Development workflow

### Daily workflow

```bash
make run-backing-services   # once per boot
make server                 # start Phoenix
make console                # attach IEx in another terminal
```

### Before committing

```bash
mix format
mix credo --strict
mix test
git commit -S -m "feat: ..."   # GPG-signed, conventional commit
```

See [CLAUDE.md](../CLAUDE.md) for the full pre-commit checklist.

### Database changes

```bash
mix ecto.gen.migration create_posts
mix ecto.migrate
mix ecto.rollback     # undo last migration
mix ecto.reset        # drop + create + migrate + seed
```

### Generate OpenAPI spec

```bash
mix openapi.spec.yaml --spec AtomicFiApi.ApiSpec
# Committed snapshot lives at packages/sdk/spec/openapi.yaml
```

---

## Troubleshooting

### Port already in use

```bash
lsof -i :4100   # find the process
kill -9 <PID>
```

### Database connection errors

```bash
# Verify the Postgres container is healthy
make deps.status
# Check DATABASE_URL in config/dev.exs or .env
```

### Backing services not starting

```bash
make deps.logs   # inspect Docker Compose output
```

### Dependency conflicts

```bash
mix deps.clean --all
mix deps.get
mix deps.compile
```

---

## IDE Setup

### VSCode

Recommended extensions: **ElixirLS**, **Tailwind CSS IntelliSense**

### Claude Code (Tidewave MCP)

Tidewave MCP is pre-configured in `.claude/settings.json`. Start the server with `make server` and Claude Code will connect automatically at `http://localhost:4100/tidewave/mcp`.

---

## Next Steps

- [Architecture Guide](architecture.md) — system design and domain model
- [Multi-Tenancy Guide](multi-tenancy.md) — RLS and tenant scoping
- [Generators Guide](generators.md) — code generation
- [Testing Guide](testing.md) — writing effective tests
- [Use Cases](use-cases.md) — compliance scenario catalog
