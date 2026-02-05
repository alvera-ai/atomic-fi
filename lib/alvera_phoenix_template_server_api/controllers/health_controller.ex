defmodule AlveraPhoenixTemplateServerApi.HealthController do
  @moduledoc """
  Health check endpoint for API monitoring.

  This endpoint is publicly accessible and does not require authentication.
  """

  use AlveraPhoenixTemplateServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias AlveraPhoenixTemplateServerApi.Schemas.HealthCheck

  tags(["System"])

  operation(:index,
    summary: "Health check",
    description: "Check if the API is healthy and responsive",
    responses: [
      ok: {"Health check response", "application/json", HealthCheck}
    ]
  )

  def index(conn, _params) do
    json(conn, %{
      status: "ok",
      version: Application.spec(:alvera_phoenix_template_server, :vsn) |> to_string(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end
end
