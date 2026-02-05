import Config

config :alvera_phoenix_template_server, :openapi_servers, [
  %{
    url: "http://localhost:4002",
    description: "Test environment"
  }
]
