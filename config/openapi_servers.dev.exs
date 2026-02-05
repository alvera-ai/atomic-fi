import Config

config :alvera_phoenix_template_server, :openapi_servers, [
  %{
    url: "http://localhost:4000",
    description: "Local development (iex -S mix phx.server)"
  }
]
