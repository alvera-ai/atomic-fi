import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/atomic_fi start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :atomic_fi, AtomicFiWeb.Endpoint, server: true
end

# AtomicFi.DocumentParser — pick up env-driven overrides for the LLM
# transport. Defaults (set at compile time in config/config.exs) point
# at local Ollama; production deployments switch via env:
#   OLLAMA_VISION_MODEL=google:gemini-1.5-pro
#   LITER_LLM_BASE_URL=https://api.googleapis.com/...
# Empty env vars are ignored (don't clobber the compile-time default).
parser_overrides =
  Enum.reject(
    [
      vision_model_id: System.get_env("OLLAMA_VISION_MODEL"),
      base_url: System.get_env("LITER_LLM_BASE_URL")
    ],
    fn {_k, v} -> v in [nil, ""] end
  )

if parser_overrides != [] do
  config :atomic_fi, :document_parser, parser_overrides
end

if config_env() == :prod do
  # Watchman sanctions screening service
  watchman_url =
    System.get_env("WATCHMAN_URL") ||
      raise "environment variable WATCHMAN_URL is missing."

  config :atomic_fi, AtomicFi.Watchman.Client, base_url: watchman_url

  # ZenRule rules/limits engine (GoRules Agent) — per-module config slice
  zen_rule_url =
    System.get_env("ZEN_RULE_URL") ||
      raise "environment variable ZEN_RULE_URL is missing."

  config :atomic_fi, AtomicFi.RuleEngine.ZenRule, base_url: zen_rule_url

  # Cloak encryption key for sensitive fields (API keys, tokens, etc.)
  cloak_key = System.get_env("CLOAK_KEY") || raise("CLOAK_KEY is missing")

  config :atomic_fi, AtomicFi.Vault,
    ciphers: [
      default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!(cloak_key)}
    ]

  # System entities for seeding (platform pattern — nested per-resource config from ENV vars)
  tenant_name =
    System.get_env("TENANT_NAME") ||
      raise """
      environment variable TENANT_NAME is missing.
      """

  tenant_slug =
    System.get_env("TENANT_SLUG") ||
      tenant_name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

  admin_email =
    System.get_env("ADMIN_USER") ||
      raise """
      environment variable ADMIN_USER is missing.
      """

  admin_pass =
    System.get_env("ADMIN_PASS") ||
      raise """
      environment variable ADMIN_PASS is missing.
      """

  bot_email =
    System.get_env("BOT_USER") || "bot@#{tenant_slug}.local"

  root_api_key =
    System.get_env("ROOT_API_KEY") ||
      raise """
      environment variable ROOT_API_KEY is missing.
      This should be a secure, randomly generated API key for root access.
      """

  config :atomic_fi, :system_tenant,
    name: tenant_name,
    slug: tenant_slug

  config :atomic_fi, :admin_user,
    email: admin_email,
    password: admin_pass

  config :atomic_fi, :bot_user, email: bot_email

  config :atomic_fi, :root_api_key, root_api_key

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6"), do: [:inet6], else: []

  config :atomic_fi, AtomicFi.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
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
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/plug_cowboy/Plug.Cowboy.html
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :atomic_fi, AtomicFiWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your endpoint, ensuring
  # no data is ever sent via http, always redirecting to https:
  #
  #     config :atomic_fi, AtomicFiWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :atomic_fi, AtomicFi.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
