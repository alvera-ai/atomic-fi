# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :payment_compliance_platform,
  ecto_repos: [PaymentCompliancePlatform.Repo],
  # Generator defaults: binary IDs and microsecond timestamps
  generators: [binary_id: true, timestamp_type: :utc_datetime_usec],
  # Row-Level Security (RLS) hierarchy
  # Architecture: Tenant-based multi-tenancy with customer isolation
  # Hierarchy is evaluated in order: tenant_id (required), then customer_id (optional)
  # If session has customer_id, RLS filters by both tenant_id and customer_id
  rls_hierarchy: [
    %{
      field: :tenant_id,
      table: :tenants,
      module: PaymentCompliancePlatform.TenantContext.Tenant
    },
    %{
      field: :customer_id,
      table: :customers,
      module: PaymentCompliancePlatform.CustomerContext.Customer
    }
  ]

# Configures the endpoint
config :payment_compliance_platform, PaymentCompliancePlatformWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [
      html: PaymentCompliancePlatformWeb.ErrorHTML,
      json: PaymentCompliancePlatformWeb.ErrorJSON
    ],
    layout: false
  ],
  pubsub_server: PaymentCompliancePlatform.PubSub,
  live_view: [signing_salt: "Q6eC1J8a"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :payment_compliance_platform, PaymentCompliancePlatform.Mailer,
  adapter: Swoosh.Adapters.Local

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
      --config=tailwind.config.js
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
config :flop, repo: PaymentCompliancePlatform.Repo, default_limit: 20

# OpenAPI Generator configuration for Watchman client
config :oapi_generator,
  watchman: [
    output: [
      base_module: PaymentCompliancePlatform.Watchman,
      location: "lib/payment_compliance_platform/watchman"
    ]
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
