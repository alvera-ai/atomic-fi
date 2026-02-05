import Config

# Production OpenAPI servers should be configured via environment variables
# Example: API_BASE_URL=https://api.example.com
config :alvera_phoenix_template_server, :openapi_servers, [
  %{
    url: System.get_env("API_BASE_URL", "https://api.example.com"),
    description: "Production API server"
  }
]
