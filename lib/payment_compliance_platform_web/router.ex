defmodule PaymentCompliancePlatformWeb.Router do
  use PaymentCompliancePlatformWeb, :router

  # Browser pipeline for web pages (including Scalar UI)
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {PaymentCompliancePlatformWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # API pipeline for JSON endpoints (includes OpenAPI spec)
  pipeline :api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: PaymentCompliancePlatformApi.ApiSpec
  end

  # API authentication pipeline (validates x-api-key header)
  pipeline :api_authenticated do
    plug PaymentCompliancePlatformApi.Plugs.ApiAuthentication
  end

  # Public health check (no pipelines for pure endpoint - for load balancers)
  scope "/", PaymentCompliancePlatformWeb do
    get "/health-check", PageController, :health_check
  end

  # Public web routes
  scope "/", PaymentCompliancePlatformWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Scalar API documentation UI (HTML/JS from CDN)
    get "/api/docs", ScalarController, :index
  end

  # Delegate API routes (uses routes.ex macro)
  scope "/" do
    use PaymentCompliancePlatformApi.Routes
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:payment_compliance_platform, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PaymentCompliancePlatformWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
