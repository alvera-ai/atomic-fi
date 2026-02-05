defmodule PaymentCompliancePlatformApi.OpenApiSpecController do
  use PaymentCompliancePlatformWeb, :controller

  alias PaymentCompliancePlatformApi.ApiSpec

  @doc """
  Returns the OpenAPI specification as JSON.
  Public endpoint used by Scalar and other API documentation tools.
  """
  def spec(conn, _params) do
    spec = ApiSpec.spec()
    json(conn, spec)
  end
end
