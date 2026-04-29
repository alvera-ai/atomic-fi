# Deployment Guide

This guide covers deploying the Payments Compliance Platform to production.

## Overview

The template supports multiple deployment strategies:

- **Docker**: Multi-arch containers (recommended)
- **Traditional**: Elixir releases
- **Cloud**: AWS, GCP, Azure, Fly.io

## Docker Deployment (Recommended)

### Dockerfile

**File**: `Dockerfile` (Multi-stage build)

```dockerfile
# Build stage
FROM hexpm/elixir:1.18.3-erlang-27.3.3-debian-bookworm-20251103-slim AS builder

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git nodejs npm \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV="prod"

# Install dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy assets
COPY assets assets
COPY priv priv

# Compile assets
RUN mix assets.deploy

# Compile application
COPY lib lib
RUN mix compile

# Build release
COPY config/runtime.exs config/
RUN mix release

# Runtime stage
FROM debian:bookworm-20251103-slim AS runner

# Install runtime dependencies
RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /app

# Create user
RUN useradd --create-home app
USER app

# Copy release
COPY --from=builder --chown=app:app /app/_build/prod/rel/atomic_fi ./

# Expose port
EXPOSE 4000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:4000/api/health || exit 1

# Start command
CMD ["/app/bin/server"]
```

### Building

```bash
# Build for current architecture
docker build -t alvera-phoenix-template .

# Build multi-arch (amd64 + arm64)
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/alvera-ai/phoenix-template:latest \
  --push \
  .
```

### Running

```bash
# Run locally
docker run -p 4000:4000 \
  -e DATABASE_URL="ecto://user:pass@host/db" \
  -e SECRET_KEY_BASE="<secret>" \
  alvera-phoenix-template

# Run with docker-compose
docker-compose up
```

### docker-compose.yml

```yaml
version: '3.8'

services:
  app:
    build: .
    ports:
      - "4000:4000"
    environment:
      DATABASE_URL: ecto://postgres:postgres@db:5432/app_prod
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
      PHX_HOST: ${PHX_HOST:-localhost}
    depends_on:
      - db

  db:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: app_prod
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

## Environment Variables

### Required

```bash
# Database
DATABASE_URL=ecto://user:pass@host:5432/database

# Phoenix
SECRET_KEY_BASE=<generate with: mix phx.gen.secret>
PHX_HOST=your-domain.com
PORT=4000

# Optional: HTTPS
SECURE_COOKIE=true
FORCE_SSL=true
```

### Optional

```bash
# Oban
OBAN_QUEUES=default:10,mailers:20

# Email (Swoosh)
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USERNAME=apikey
SMTP_PASSWORD=<api_key>

# OAuth (if enabled)
OIDC_ISSUER=https://your-keycloak.com/realms/your-realm
OIDC_CLIENT_ID=your_client_id
OIDC_CLIENT_SECRET=your_client_secret
```

## Release Configuration

### config/runtime.exs

```elixir
import Config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :atomic_fi, AtomicFi.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :atomic_fi, AtomicFiWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # Mailer
  config :atomic_fi, AtomicFi.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: System.get_env("SMTP_HOST"),
    port: System.get_env("SMTP_PORT"),
    username: System.get_env("SMTP_USERNAME"),
    password: System.get_env("SMTP_PASSWORD"),
    tls: :always
end
```

## GitHub Container Registry (GHCR)

### GitHub Actions

**File**: `.github/workflows/docker.yml`

```yaml
name: Docker Build

on:
  push:
    branches: [main]
    tags: ['v*']

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build-amd64:
    runs-on: ubuntu-24.04
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha,prefix={{branch}}-

      - name: Build and push AMD64
        uses: docker/build-push-action@v5
        with:
          context: .
          platforms: linux/amd64
          push: true
          tags: ${{ steps.meta.outputs.tags }}-amd64
          labels: ${{ steps.meta.outputs.labels }}

  build-arm64:
    runs-on: [self-hosted, ARM64]  # Or use QEMU
    permissions:
      contents: read
      packages: write

    steps:
      # Similar to amd64 but with platform: linux/arm64

  create-manifest:
    needs: [build-amd64, build-arm64]
    runs-on: ubuntu-24.04

    steps:
      - name: Create and push manifest
        run: |
          docker buildx imagetools create \
            -t ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest \
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:main-amd64 \
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:main-arm64

  security-scan:
    needs: [create-manifest]
    runs-on: ubuntu-24.04

    steps:
      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'

      - name: Upload Trivy results
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: 'trivy-results.sarif'
```

## Database Migrations

### Production Migrations

```bash
# Inside container
/app/bin/atomic_fi eval "AtomicFi.Release.migrate"

# Or via release command
/app/bin/atomic_fi rpc "AtomicFi.Release.migrate()"
```

### Migration Module

**File**: `lib/atomic_fi/release.ex`

```elixir
defmodule AtomicFi.Release do
  @moduledoc """
  Tasks to run in production releases
  """

  @app :atomic_fi

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
```

## Cloud Deployments

### Fly.io

```bash
# Install flyctl
curl -L https://fly.io/install.sh | sh

# Launch app
fly launch

# Deploy
fly deploy

# Open app
fly open
```

**File**: `fly.toml`

```toml
app = "alvera-phoenix-template"
primary_region = "iad"

[build]

[env]
  PHX_HOST = "alvera-phoenix-template.fly.dev"
  PORT = "8080"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = true
  auto_start_machines = true
  min_machines_running = 0
  processes = ["app"]

[[vm]]
  cpu_kind = "shared"
  cpus = 1
  memory_mb = 1024
```

### AWS (ECS)

1. Push image to ECR
2. Create ECS task definition
3. Create ECS service
4. Set up ALB for HTTPS
5. Configure RDS for database

### Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: phoenix-template
spec:
  replicas: 3
  selector:
    matchLabels:
      app: phoenix-template
  template:
    metadata:
      labels:
        app: phoenix-template
    spec:
      containers:
      - name: app
        image: ghcr.io/alvera-ai/phoenix-template:latest
        ports:
        - containerPort: 4000
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: url
        - name: SECRET_KEY_BASE
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: secret-key-base
```

## Monitoring

### Health Check Endpoint

**File**: `lib/atomic_fi_web/controllers/health_controller.ex`

```elixir
defmodule AtomicFiWeb.HealthController do
  use AtomicFiWeb, :controller

  def index(conn, _params) do
    # Check database
    case Ecto.Adapters.SQL.query(AtomicFi.Repo, "SELECT 1", []) do
      {:ok, _} ->
        json(conn, %{status: "healthy", timestamp: DateTime.utc_now()})

      {:error, _} ->
        conn
        |> put_status(503)
        |> json(%{status: "unhealthy", reason: "database_unavailable"})
    end
  end
end
```

### Logging

Production uses structured JSON logging:

```elixir
# config/prod.exs
config :logger, :default_handler,
  formatter: {LoggerJSON.Formatters.GoogleCloud, []}

config :logger_json, :backend,
  metadata: :all,
  formatter: LoggerJSON.Formatters.GoogleCloud
```

### Telemetry

Monitor with LiveDashboard (protected):

```elixir
# config/prod.exs
config :atomic_fi, AtomicFiWeb.Endpoint,
  live_dashboard_auth: {AtomicFiWeb.Auth, :require_admin}
```

## Secrets Management

### Using AWS Secrets Manager

```elixir
# config/runtime.exs
defmodule Secrets do
  def fetch_secret(secret_name) do
    ExAws.SecretsManager.get_secret_value(secret_name)
    |> ExAws.request()
    |> case do
      {:ok, %{"SecretString" => secret}} -> Jason.decode!(secret)
      {:error, _} -> raise "Failed to fetch secret: #{secret_name}"
    end
  end
end

config :atomic_fi, AtomicFi.Repo,
  url: Secrets.fetch_secret("DATABASE_URL")["url"]
```

## Performance

### Production Checklist

- [ ] Enable SSL/TLS
- [ ] Set up CDN for static assets
- [ ] Configure database connection pooling
- [ ] Enable response compression
- [ ] Set up horizontal pod autoscaling
- [ ] Configure caching headers
- [ ] Enable HTTP/2
- [ ] Set up monitoring and alerting

### Optimization

```elixir
# config/prod.exs

# Enable code reloading in console
config :phoenix, :plug_init_mode, :runtime

# Compile-time compression
config :phoenix, :serve_endpoints, true

# Bandit (faster than Cowboy)
config :atomic_fi, AtomicFiWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter
```

## Rollback Strategy

```bash
# Via Docker tag
docker pull ghcr.io/alvera-ai/phoenix-template:v1.0.0
docker run ghcr.io/alvera-ai/phoenix-template:v1.0.0

# Via Kubernetes
kubectl set image deployment/phoenix-template \
  app=ghcr.io/alvera-ai/phoenix-template:v1.0.0

# Rollback migration
/app/bin/atomic_fi rpc \
  "AtomicFi.Release.rollback(AtomicFi.Repo, 20240101000000)"
```

## Next Steps

- [Architecture Guide](architecture.md) - Production architecture
- [Testing Guide](testing.md) - CI/CD testing
- [API Development](api-development.md) - API deployment
