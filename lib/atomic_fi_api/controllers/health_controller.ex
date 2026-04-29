defmodule AtomicFiApi.HealthController do
  @moduledoc """
  Health check endpoint for API monitoring.

  This endpoint is publicly accessible and does not require authentication.
  """

  use AtomicFiWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFiApi.Schemas.HealthCheck

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
      version: Application.spec(:atomic_fi, :vsn) |> to_string(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end
end
