import Config

config :payment_compliance_platform, :openapi_servers, [
  %{
    url: "http://localhost:4002",
    description: "Test environment"
  }
]
