import Config

config :atomic_fi, :openapi_servers, [
  %{
    url: "http://localhost:4100",
    description: "Local development (iex -S mix phx.server)"
  }
]
