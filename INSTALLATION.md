# Installation

## Option 1 — Compile and run locally

### Prerequisites

- Elixir 1.18.3-otp-27 / Erlang 27.3.3 (see `.tool-versions`)
- Docker (for backing services)
- pnpm (`corepack enable` or `brew install pnpm`)

```bash
# Install Elixir/Erlang via asdf
asdf plugin add elixir && asdf plugin add erlang && asdf install
```

### Steps

```bash
# 1. Install dependencies
mix deps.get
pnpm install

# 2. Start backing services (Postgres, Watchman, ZenRule, Mockoon, CopilotKit)
make run-backing-services

# 3. Create DB, run migrations, seed
mix ecto.setup
make seed

# 4. Start the server
make server
```

Visit **http://localhost:4100** — API docs at `/api/docs`.

### LLM configuration (compile and run)

`make server` sources `.env` from the repo root before starting Phoenix. Add your keys there:

```bash
# .env
LOTUS_AI_MODEL=google:gemini-2.5-flash
LOTUS_AI_API_KEY=your-api-key-here

LLM_PROVIDER=google
LLM_MODEL=gemini-2.5-flash
GOOGLE_API_KEY=your-api-key-here
```

---

## Option 2 — Docker Compose (no local Elixir needed)

### Prerequisites

- Docker with Compose

### Steps

```bash
# (Optional) configure AI features — see LLM section below
cp .env.example .env

# Start everything
docker compose up
```

This is the single command — it builds **everything**: the three Vite demo
SPAs and Phoenix assets are compiled into the `app` image (`MIX_ENV=prod`), and
a one-shot `hydrate` service seeds the sanctions list + decision rules into the
Watchman/ZenRule containers. No `make` prep steps. The first build takes a few
minutes (Node + Elixir compile); subsequent boots are fast.

On boot the `app` container runs `mix ecto.setup` (creates the DB, migrates, and
seeds the system tenant/admin) then starts Phoenix. All other services
(Postgres, Watchman, ZenRule, Mockoon, CopilotKit) start automatically and in
the correct order.

Visit **http://localhost:4100** — API docs at `/api/docs`, demo apps under
`/demo/{onboarding-flow,atomic-fi-jdm-editor,lotus-embed}/`.

To stop:

```bash
docker compose down
```

### Reset to a clean state

If a teammate hits cache-induced drift (stale image, leftover volume), reset to
a reproducible state — this drops the named volumes (`pgdata`, `zenrule-data`,
`watchman-data`) and rebuilds every image from scratch:

```bash
docker compose down -v --remove-orphans   # stop + drop volumes
docker compose build --no-cache           # rebuild images fresh
docker compose up                          # clean boot
```

For a deeper clean of dangling build layers: `docker builder prune -f`.

### Troubleshooting: build times out fetching deps

If `docker compose build` hangs or fails while fetching JS/Rust deps — e.g.
`pnpm install` → corepack `ETIMEDOUT`, or cargo unable to reach crates.io —
while your host browser/CLI can reach those sites fine, the Docker **build
network** can't egress (common behind a corporate VPN or proxy: image *pulls*
work via the daemon, but `RUN` steps use the build bridge, which lacks the
route). Fixes, in order of preference:

1. **Docker Desktop proxy** — Settings → Resources → Proxies → enter your
   HTTP/HTTPS proxy. Docker injects it into builds. The clean fix on a
   proxied/VPN network.
2. **VPN** — disconnect, or split-tunnel so the Docker subnet has egress.
3. **One-off host network** — build with the host's network (which has the
   route), then bring the stack up normally:
   ```bash
   docker build --network=host -t atomic-fi-app .   # app image
   docker compose up                                 # uses the built image
   ```
   (Or add `build: { network: host }` per service in a local
   `docker-compose.override.yml` — not committed, so the base compose stays
   portable for teammates without the VPN.)

### LLM configuration (Docker Compose)

Both the `app` service and the `copilot-runtime` service read `.env` via `env_file`. Same file, no extra steps:

```bash
# .env
LOTUS_AI_MODEL=google:gemini-2.5-flash
LOTUS_AI_API_KEY=your-api-key-here

LLM_PROVIDER=google
LLM_MODEL=gemini-2.5-flash
GOOGLE_API_KEY=your-api-key-here
```

The `copilot-runtime` defaults (Ollama on `host.docker.internal:11434`) live in `external-deps/copilot-runtime/docker.env`. Values in `.env` override them.

Which key drives which feature:

| Feature | Service | Env vars |
|---|---|---|
| JDM editor copilot (`/demo/atomic-fi-jdm-editor/`) | `copilot-runtime` | `LLM_PROVIDER`, `LLM_MODEL`, `GOOGLE_API_KEY` / `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` |
| Document parser (`/api/parse`) | `app` | `OLLAMA_VISION_MODEL`, `LITER_LLM_BASE_URL` |
| Lotus SQL copilot (`/lotus`) | `app` | `LOTUS_AI_MODEL` (`<provider>:<model>`), `LOTUS_AI_API_KEY` |

> After editing `.env`, run `docker compose up -d` again — it recreates the
> containers so the new `env_file` values load (`restart` alone won't re-read it).

---

## Default credentials

After `mix ecto.setup` (or first `docker compose up`), the following accounts exist:

| Role | Email | Password |
|---|---|---|
| Admin | `admin@atomic-fi.local` | `admin-password-dev` |
| Tenant admin (demo) | `tenant-admin@atomic-fi.local` | `demo-password` |
| Tenant user (demo) | `user@atomic-fi.local` | `demo-password` |

The root API key for local dev is `alvera_root_api_key_dev`. Pass it as a Bearer token:

```bash
curl -H "Authorization: Bearer alvera_root_api_key_dev" http://localhost:4100/api/account-holders
```

> These credentials are hardcoded in `config/dev.exs` and `priv/repo/seeds.exs`. Never use them in production.

---

## LLM providers

There are two AI features, each configured separately:

| Feature | Env vars | Default |
|---|---|---|
| Lotus SQL copilot (UI) | `LOTUS_AI_MODEL`, `LOTUS_AI_API_KEY` | Ollama `qwen2.5:7b` |
| JDM rule editor copilot (CopilotKit sidecar) | `LLM_PROVIDER`, `LLM_MODEL`, `<PROVIDER>_API_KEY` | Ollama `qwen3.5:9b` |

`LOTUS_AI_MODEL` uses `<provider>:<model>` format. `LLM_PROVIDER` / `LLM_MODEL` are separate vars:

| Provider | `LOTUS_AI_MODEL` | `LLM_PROVIDER` |
|---|---|---|
| Google Gemini | `google:gemini-2.5-flash` | `google` |
| Anthropic | `anthropic:claude-sonnet-4-6` | `anthropic` |
| OpenAI | `openai:gpt-4o` | `openai` |
| Ollama (local) | `ollama:qwen2.5:7b` | `ollama` |

### Ollama (default, no API key needed)

```bash
brew install ollama && ollama serve
ollama pull llama3.2-vision:11b   # document parser (/api/parse)
ollama pull qwen2.5:7b            # Lotus SQL copilot
ollama pull qwen3.5:9b            # JDM editor copilot
```

Docker Compose reaches Ollama on the host via `host.docker.internal:11434` — no extra config needed.

---

## Bruno collection

A runnable Bruno collection covering all compliance scenarios lives in [`bruno/atomic-fi-scenarios/`](bruno/atomic-fi-scenarios/). It requires the server to be running.

```bash
# Install Bruno CLI
npm install -g @usebruno/cli

# Run all scenarios against the local environment
bru run bruno/atomic-fi-scenarios --env local

# Or via make
make test-bruno
```

Scenarios included:

| Scenario | Description |
|---|---|
| `ofac-sdn-high-score` | OFAC SDN high-confidence match |
| `ofac-mixer-usdc` | OFAC virtual currency mixer |
| `de-minimis-ach` | De minimis ACH transaction screening |
| `id-dttot-match` | Indonesian DTTOT sanctions list match |
| `id-pep-edd` | Indonesian PEP + enhanced due diligence |
| `id-ncj-block` | Indonesian NCJ block |
| `id-ctr-threshold` | Indonesian CTR threshold |
| `ctr-sub-threshold-structuring` | Sub-threshold structuring detection |
| `smurfing-pattern-sar-eligible` | Smurfing pattern SAR eligibility |
| `cip-kyc-in-progress` | CIP/KYC in-progress gate |
| `business-ah-zero-bos` | Business account holder with zero beneficial owners |
| `ah-country-kp-residence` | Account holder with DPRK residence |
| `prohibited-risk-freeze` | Prohibited risk level freeze |
| `internal-blocklist-lastname` | Internal blocklist last name match |
| `sanctions-screening-preview` | Sanctions screening preview |
| `smoke-tests` | Basic API smoke tests |

Environment config is in [`bruno/atomic-fi-scenarios/environments/`](bruno/atomic-fi-scenarios/environments/).
