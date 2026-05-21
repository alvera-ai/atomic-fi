defmodule AtomicFiWeb.PageController do
  use AtomicFiWeb, :controller

  # The set of demos served from `priv/static/demo/<slug>/`. Adding a
  # new demo = (a) one entry here, (b) one watcher in `config/dev.exs`,
  # (c) the per-app `vite.config.ts` base + outDir, (d) a `.gitignore`
  # line. Plug.Static (endpoint) serves the built ASSETS; `demo_app/2`
  # below is the SPA fallback that serves `index.html` for the app
  # root and any client-side route.
  @example_apps [
    %{
      slug: "onboarding-flow",
      label: "Onboarding flow",
      description: "Document extraction (POST /api/parse)"
    },
    %{
      slug: "atomic-fi-jdm-editor",
      label: "JDM editor + copilot",
      description: "CopilotKit-driven rule editor (POST /api/copilotkit)"
    },
    %{
      slug: "lotus-embed",
      label: "Lotus dashboard embed",
      description: "Embedded Lotus SQL editor + dashboard"
    }
  ]

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
    render(conn, :home, layout: false, example_apps: @example_apps)
  end

  @example_app_slugs Enum.map(@example_apps, & &1.slug)

  @doc """
  SPA fallback for an example app.

  Plug.Static (mounted at `/` in the endpoint) serves the built assets
  under `/demo/<app>/assets/*`, but has no directory-index or
  SPA-fallback behaviour — a bare `GET /demo/<app>/` or a deep link
  like `/demo/<app>/start` falls through to the router and reaches
  here. We return the app's `index.html` with a 200 so its React
  Router (configured with `basename = /demo/<app>/`) can match the
  route client-side. Only non-file paths ever reach this action,
  since Plug.Static runs first and grabs real asset requests.
  """
  def demo_app(conn, %{"app" => app}) when app in @example_app_slugs do
    index =
      :atomic_fi
      |> :code.priv_dir()
      |> Path.join("static/demo/#{app}/index.html")

    if File.exists?(index) do
      conn
      |> put_resp_content_type("text/html")
      |> send_file(200, index)
    else
      conn
      |> put_status(:not_found)
      |> text(
        "Demo '#{app}' is not built yet — run `make server` (its Vite " <>
          "watcher builds into priv/static/demo/#{app}/)."
      )
    end
  end

  def demo_app(conn, %{"app" => app}) do
    conn
    |> put_status(:not_found)
    |> text("Unknown demo: #{app}")
  end
end
