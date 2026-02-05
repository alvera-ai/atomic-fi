defmodule PaymentCompliancePlatformWeb.ScalarController do
  use PaymentCompliancePlatformWeb, :controller

  @doc """
  Renders Scalar API documentation UI.
  Scalar is loaded from CDN and points to our OpenAPI spec endpoint.
  """
  def index(conn, _params) do
    # Get the base URL for the OpenAPI spec
    base_url = PaymentCompliancePlatformWeb.Endpoint.url()
    spec_url = "#{base_url}/api/openapi"

    render(conn, :index, spec_url: spec_url, layout: false)
  end
end
