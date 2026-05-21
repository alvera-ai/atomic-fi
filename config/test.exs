import Config

# System entities for seeding (platform pattern — nested per-resource config)
config :atomic_fi, env: :test

config :atomic_fi, :system_tenant,
  name: "atomic-fi-tenant",
  slug: "atomic-fi-tenant"

config :atomic_fi, :admin_user,
  email: "admin@atomic-fi.local",
  password: "admin-password-test"

config :atomic_fi, :bot_user, email: "bot@atomic-fi.local"

config :atomic_fi, :root_api_key, "alvera_root_api_key_test"

# Watchman base URL — per-module slice (Swoosh-style); used by Watchman.Client when delegated to in tests.
config :atomic_fi, AtomicFi.Watchman.Client, base_url: "http://localhost:8084"

# Swap the screening engine to a Mox mock. DataCase/ConnCase setup hooks
# stub_with the Default impl so existing tests keep hitting the live :8084
# Watchman container; new tests can override per-call with Mox.expect/3 to
# return canned screening results without setting up Watchman state.
config :atomic_fi, :screening_engine, AtomicFi.ScreeningEngineMock

# Swap the rule engine to a Mox mock. DataCase/ConnCase setup hooks
# stub_with the real engine so existing tests keep hitting the live :8090
# GoRules Agent; new tests can override per-call with Mox.expect/3 to
# return canned limits without setting up ZenRule state.
config :atomic_fi, :rule_engine, AtomicFi.RuleEngineMock
config :atomic_fi, AtomicFi.RuleEngine, base_url: "http://localhost:8090"

# Extend RulesContext with two test-only rule_types, each a subfolder of the
# shared "test-fixtures" ZenRule project. Prod's compiled binary doesn't see
# these — Application.compile_env reads this map at test compile time only.
config :atomic_fi, AtomicFi.RulesContext,
  rule_types: %{
    onboarding: "onboarding",
    transaction_screening: "transaction-screening",
    test_fixtures_good: "test-fixtures-good",
    test_fixtures_bad: "test-fixtures-bad",
    test_fixtures_bad_caps: "test-fixtures-bad-caps"
  }

# Configure encryption vault
config :atomic_fi, AtomicFi.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1", key: Base.decode64!("3nGslycHroShfsRKvmMSsURKZrJuK6euXTKkMYfD8+8=")}
  ]

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :atomic_fi, AtomicFi.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "atomic_fi_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# LotusRepo — same DB, no RLS enforcement (Lotus needs unscoped schema access)
config :atomic_fi, AtomicFi.LotusRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "atomic_fi_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :atomic_fi, AtomicFiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4102],
  secret_key_base: "Gmo/T2R4qAj3tgdRvXjkFTeDk9KK4iqI/DbGpWH/8zaCM2GojJ9j/AbMGv5dSMP1",
  server: false

# In test we don't send emails.
config :atomic_fi, AtomicFi.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Oban - manual mode: jobs are inserted into DB sandbox, drained explicitly in tests
config :atomic_fi, Oban, testing: :manual

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Import OpenAPI server configuration
import_config "openapi_servers.#{config_env()}.exs"

# Migration paths inherit from config.exs (migrations + seed_migrations); no override.

# Local test overrides — points the LLM-backed features (document parser,
# JDM copilot, Lotus AI) at a real local Ollama (see config/test.secret.exs).
# Optional + gitignored, per-developer. Once WireMock LLM stubs land they
# become the test.exs default and this file is the opt-out back to Ollama.
if File.exists?(Path.expand("test.secret.exs", __DIR__)) do
  import_config "test.secret.exs"
end
