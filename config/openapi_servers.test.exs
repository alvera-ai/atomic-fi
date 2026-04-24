import Config

config :payment_compliance_platform, :openapi_servers, [
  %{
    url: "http://localhost:4102",
    description: "Test environment"
  }
]
