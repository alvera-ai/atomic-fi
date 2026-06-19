# Single-command production image for `docker compose up`.
#
# Unlike Dockerfile.dev (backend-only, dev watchers expected on the host), this
# image builds the full product: the three Vite demo SPAs + Phoenix assets are
# compiled ahead of time and served by Plug.Static, so the runtime needs no
# Node, no esbuild/tailwind watchers, and binds 0.0.0.0 for host access.
#
#   stage `assets` (node)   -> pnpm build x3 -> priv/static/demo/<app>/
#   stage `app`    (elixir) -> mix assets.deploy + compile (MIX_ENV=prod)
#
# Dockerfile.dev is intentionally left untouched for the native/dev path.

# ─── Stage 1: build the Vite demo SPAs ────────────────────────────────
FROM node:22-alpine AS assets

# libc6-compat: musl shim for @swc/core native bindings used by the React
# SWC plugin. git: some transitive deps resolve via git.
RUN apk add --no-cache libc6-compat git
RUN corepack enable

WORKDIR /app

# Workspace skeleton first so `pnpm install` layer-caches on lockfile changes
# only. `patches/` is required by the root package.json pnpm.patchedDependencies
# (@gorules/jdm-editor). All workspace members are copied so --frozen-lockfile
# can verify the full graph (node_modules are excluded via .dockerignore).
COPY pnpm-workspace.yaml package.json pnpm-lock.yaml ./
COPY patches ./patches
COPY packages ./packages
COPY example-apps ./example-apps
COPY atomic-fi-web ./atomic-fi-web
COPY integration-tests ./integration-tests

RUN pnpm install --frozen-lockfile

# Each vite config writes to ../../priv/static/demo/<app> (path-relative to the
# app dir), so with the repo at /app the output lands in /app/priv/static/demo/.
RUN pnpm --filter onboarding-flow build \
 && pnpm --filter @atomic-fi/jdm-editor build \
 && pnpm --filter lotus-embed build

# ─── Stage 2: compile Elixir + Phoenix assets, run in prod ────────────
FROM hexpm/elixir:1.18.3-erlang-27.3.3-debian-bookworm-20250428-slim AS app

RUN apt-get update && apt-get install -y \
      git build-essential ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

# Deps first for layer caching.
COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force && mix deps.get --only prod

COPY config config
RUN mix deps.compile

# Application source + runtime data (mirrors Dockerfile.dev: rules_context.ex
# and the blocklist normalizer read these out of priv at runtime).
COPY lib lib
COPY priv priv
COPY assets assets
COPY zen_rules zen_rules
COPY corpus corpus
COPY Makefile Makefile
COPY custom-watchlist.jsonl config.all-lists.yml ./

# Populate priv/zenrule/{onboarding,transaction-screening} from zen_rules/ —
# the app's RuleEngine reads rule JSON from priv at runtime.
RUN make hydrate-zen-rules

# Built SPAs from the assets stage, then digest everything (tailwind + esbuild
# + phx.digest). esbuild/tailwind run as standalone hex-managed binaries — no
# Node needed here.
COPY --from=assets /app/priv/static/demo priv/static/demo
RUN mix assets.deploy
RUN mix compile

EXPOSE 4100

# ecto.setup = create + enhanced migrate (seeds system tenant/admin from the
# prod env vars supplied by docker-compose). Idempotent on re-runs.
CMD ["sh", "-c", "mix ecto.setup && PHX_SERVER=true mix phx.server"]
