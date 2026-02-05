defmodule PaymentCompliancePlatformWeb.PageController do
  use PaymentCompliancePlatformWeb, :controller

  @doc """
  Simple health check endpoint for load balancers and monitoring.
  Returns 200 OK if server is responsive. Does not check database.
  """
  def health_check(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end
end
