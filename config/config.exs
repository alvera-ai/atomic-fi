# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :atomic_fi,
  ecto_repos: [AtomicFi.Repo],
  env: config_env(),
  # Generator defaults: binary IDs and microsecond timestamps
  generators: [binary_id: true, timestamp_type: :utc_datetime_usec],
  # Row-Level Security (RLS) hierarchy
  # Architecture: single-tenant per deployment; every row scoped by tenant_id.
  rls_hierarchy: [
    %{
      field: :tenant_id,
      table: :tenants,
      module: AtomicFi.TenantContext.Tenant
    }
  ]

# AtomicFi.DocumentParser defaults — Ollama via ReqLLM's OpenAI-compat
# path. Production deployments can switch the provider by overriding
# `vision_model_id` + `base_url` (set in config/runtime.exs from
# OLLAMA_VISION_MODEL / LITER_LLM_BASE_URL env vars, or replace with
# `google:gemini-1.5-pro` / `anthropic:claude-...` for cloud models).
config :atomic_fi, :document_parser,
  vision_model_id: "llama3.2-vision:11b",
  base_url: "http://localhost:11434/v1"

# Configures the endpoint
config :atomic_fi, AtomicFiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [
      html: AtomicFiWeb.ErrorHTML,
      json: AtomicFiWeb.ErrorJSON
    ],
    layout: false
  ],
  pubsub_server: AtomicFi.PubSub,
  live_view: [signing_salt: "Q6eC1J8a"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :atomic_fi, AtomicFi.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.14.41",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.2.4",
  default: [
    args: ~w(
      --config=tailwind.config.cjs
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :session_id,
    :role_id,
    :role_name,
    :tenant_id,
    :tenant_name,
    :customer_id,
    :api_key_id,
    :api_key_name,
    :trace_id,
    :mfa
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Flop for pagination
config :flop, repo: AtomicFi.Repo, default_limit: 20

# Default enabled regimes — the global root of the regime hierarchy.
# Tenant inherits this when its own :enabled_regimes is unset; AccountHolder
# inherits Tenant; PaymentAccount inherits AccountHolder (or Counterparty if
# `counterparty_id` is set); Counterparty inherits Tenant. At every level
# an explicit override is allowed but must be a subset of the parent's
# effective regimes. See `AtomicFi.EnabledRegimes`.
config :atomic_fi, :enabled_regimes, ["ach", "wire", "card", "stablecoin", "internal_transfer"]

# Watchman sanctions screening service — per-module config slice (Swoosh-style)
config :atomic_fi, AtomicFi.Watchman.Client, base_url: "http://localhost:8084"

# ZenRule rules/limits engine (GoRules Agent). The rule_engine impl satisfies
# the `AtomicFi.RuleEngine` behaviour (per-rule `evaluate_rule/4`) and is
# consulted synchronously when a
# Transaction/AccountHolder/Counterparty is created or updated. Mirrors the
# ScreeningEngine seam — the caller picks the impl via
# `Application.compile_env` (RuleEngine in prod; RuleEngineMock in test).
config :atomic_fi, :rule_engine, AtomicFi.RuleEngine.Default
config :atomic_fi, AtomicFi.RuleEngine, base_url: "http://localhost:8090"

# RulesContext rule-type → ZenRule project name (which is also the on-disk
# subdir under priv/zenrule/). Tests can extend this map in config/test.exs
# without prod's compiled binary seeing the extra types — Application.compile_env
# reads the map at compile time per MIX_ENV.
config :atomic_fi, AtomicFi.RulesContext,
  rule_types: %{
    onboarding: "onboarding",
    transaction_screening: "transaction-screening"
  }

# Oban background job processing
config :atomic_fi, Oban,
  prefix: "oban",
  repo: AtomicFi.Repo,
  queues: [onboarding: 10]

# Quantum scheduler - cron-like job scheduling
config :atomic_fi, AtomicFi.Scheduler,
  jobs: [
    # Refresh blocklist cache every hour
    {"0 * * * *", {AtomicFi.BlocklistContext.BlocklistCache, :refresh_all_caches, []}}
  ]

# Migration paths: schema migrations run first, then seed_migrations bootstrap
# the system tenant, roles, admin/bot users, and root API key. This makes the
# platform usable after a single `mix ecto.migrate`. Mirrors platform pattern.
config :atomic_fi, :migration_paths, %{
  AtomicFi.Repo => ["priv/repo/migrations", "priv/repo/seed_migrations"]
}

# Lotus — embeddable SQL editor & dashboard
config :lotus,
  ecto_repo: AtomicFi.LotusRepo,
  default_repo: "atomic_fi",
  data_repos: %{
    "atomic_fi" => AtomicFi.LotusRepo
  },
  cache: %{
    adapter: Lotus.Cache.ETS,
    namespace: "atomic_fi_lotus"
  }

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
