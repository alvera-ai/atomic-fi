import Config

# System entities for seeding (CRM pattern - just names, not full configs)
config :payment_compliance_platform,
  env: :test,
  tenant_name: "System",
  admin_user: "admin@system.local",
  admin_pass: "admin-password-test",
  bot_user: "bot@system.local",
  root_api_key: "alvera_root_api_key_test"

# Watchman client (uses Req.Test mocking in tests)
config :payment_compliance_platform, :watchman_base_url, "http://localhost:8084"

# Configure encryption vault
config :payment_compliance_platform, PaymentCompliancePlatform.Vault,
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
config :payment_compliance_platform, PaymentCompliancePlatform.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "payment_compliance_platform_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :payment_compliance_platform, PaymentCompliancePlatformWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Gmo/T2R4qAj3tgdRvXjkFTeDk9KK4iqI/DbGpWH/8zaCM2GojJ9j/AbMGv5dSMP1",
  server: false

# In test we don't send emails.
config :payment_compliance_platform, PaymentCompliancePlatform.Mailer,
  adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Import OpenAPI server configuration
import_config "openapi_servers.#{config_env()}.exs"

# Override migration paths for test environment to include test_migrations
config :payment_compliance_platform, :migration_paths, %{
  PaymentCompliancePlatform.Repo => ["priv/repo/migrations", "priv/repo/test_migrations"]
}
