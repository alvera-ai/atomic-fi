defmodule AtomicFiWeb.PageController do
  use AtomicFiWeb, :controller

  # The set of demos served from `priv/static/demo/<slug>/`. Adding a
  # new demo = (a) one entry here, (b) one watcher in `config/dev.exs`,
  # (c) the per-app `vite.config.ts` base + outDir, (d) a `.gitignore`
  # line. Plug.Static handles serving — no DemoController.
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
end
