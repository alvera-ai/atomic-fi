defmodule AtomicFiWeb.ScalarController do
  use AtomicFiWeb, :controller

  @doc """
  Renders Scalar API documentation UI.
  Scalar is loaded from CDN and points to our OpenAPI spec endpoint.
  """
  def index(conn, _params) do
    render(conn, :index, spec_url: "/api/openapi", layout: false)
  end
end
