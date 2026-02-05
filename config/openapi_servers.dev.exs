import Config

config :payment_compliance_platform, :openapi_servers, [
  %{
    url: "http://localhost:4000",
    description: "Local development (iex -S mix phx.server)"
  }
]
