defmodule AtomicFiWeb.Router do
  use AtomicFiWeb, :router
  import Lotus.Web.Router

  # Browser pipeline for web pages (including Scalar UI)
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {AtomicFiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # Lotus embed pipeline — iframe-friendly (no X-Frame-Options)
  pipeline :lotus_embed do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {AtomicFiWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "x-frame-options" => "",
      "content-security-policy" => ""
    }

    plug AtomicFiWeb.Plugs.EmbedTokenAuth
  end

  # API pipeline for JSON endpoints (includes OpenAPI spec)
  pipeline :api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: AtomicFiApi.ApiSpec
  end

  # API authentication pipeline (validates x-api-key header)
  pipeline :api_authenticated do
    plug AtomicFiApi.Plugs.ApiAuthentication
  end

  # Public health check (no pipelines for pure endpoint - for load balancers)
  scope "/", AtomicFiWeb do
    get "/health-check", PageController, :health_check
  end

  # Public web routes
  scope "/", AtomicFiWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Scalar API documentation UI (HTML/JS from CDN)
    get "/api/docs", ScalarController, :index
  end

  # Delegate API routes (uses routes.ex macro)
  scope "/" do
    use AtomicFiApi.Routes
  end

  # Lotus dashboard — authenticated via embed token in query param
  scope "/" do
    pipe_through :lotus_embed

    lotus_dashboard("/lotus")
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:atomic_fi, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AtomicFiWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
