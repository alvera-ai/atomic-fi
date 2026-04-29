import Config

config :atomic_fi, :openapi_servers, [
  %{
    url: "http://localhost:4102",
    description: "Test environment"
  }
]
