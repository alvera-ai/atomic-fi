defmodule AtomicFi.MixProject do
  use Mix.Project

  def project do
    [
      app: :atomic_fi,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      source_url: "https://github.com/alvera-ai/atomic-fi",
      homepage_url: "https://github.com/alvera-ai/atomic-fi",
      listeners: [Phoenix.CodeReloader],
      test_coverage: [tool: ExCoveralls]
    ]
  end

  # Mix 1.19 moved preferred CLI envs out of project/0.
  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        "coveralls.xml": :test,
        "coveralls.lcov": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  defp description do
    "Payments and compliance, welded into one atomic database transaction. " <>
      "Compliance gating (KYC/KYB/AML, OFAC, UBO) and a double-entry ledger commit or fail together."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/alvera-ai/atomic-fi"},
      maintainers: ["AtomicFi contributors"]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {AtomicFi.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # Phoenix base
      {:phoenix, "~> 1.8.3"},
      {:phoenix_ecto, "~> 4.6"},
      {:ecto_sql, "~> 3.12"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1", override: true},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_live_view, "~> 1.0.1", override: true},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:floki, ">= 0.34.3"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.11"},
      {:phoenix_swoosh, "~> 1.2.1"},
      {:finch, "~> 0.19"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26", override: true},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.8"},
      {:dns_cluster, "~> 0.2"},
      {:logger_json, "~> 5.1"},

      # Background jobs (open-source Oban, not Oban Pro)
      {:oban, "~> 2.20"},

      # Cron-like job scheduler
      {:quantum, "~> 3.5"},

      # Ecto querying / pagination
      {:query_builder, "~> 1.4"},
      {:flop, "~> 0.25"},
      {:typed_ecto_schema, "~> 0.4.1"},

      # Authentication
      {:bcrypt_elixir, "~> 3.3"},
      {:nimble_totp, "~> 1.0"},
      {:eqrcode, "~> 0.2"},
      {:ueberauth, "~> 0.10"},
      {:ueberauth_oidc, "~> 0.1"},

      # Encryption
      {:cloak_ecto, "~> 1.3"},

      # API & OpenAPI
      {:ex_open_api_utils, "~> 0.17.0"},
      {:cachex, "~> 4.0"},

      # Petal components and framework
      {:petal_components, "~> 3.0"},

      # HTTP client
      {:req, "~> 0.5"},

      # Lotus — embeddable SQL editor & dashboard (LiveView)
      {:lotus_web, "~> 0.14.5"},

      # Money / currency arithmetic
      {:money, "~> 1.12"},

      # Utils
      {:slugify, "~> 1.3"},
      {:timex, "~> 3.7", override: true},
      {:rename, "~> 0.1.0", only: :dev},

      # Testing
      {:wallaby, "~> 0.30", runtime: false, only: :test},
      {:ex_machina, "~> 2.8", only: :test},
      {:mimic, "~> 1.10", only: :test},
      {:mox, "~> 1.2", only: :test},
      {:exvcr, "~> 0.15", only: :test},

      # Code quality
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false},

      # Development tools
      {:tidewave, "~> 0.5.2", only: :dev},
      {:phoenix_storybook, github: "phenixdigital/phoenix_storybook", branch: "main", only: :dev},
      {:ex_doc, "~> 0.39", runtime: false},

      # OpenAPI client generation
      {:oapi_generator, "~> 0.2", only: :dev, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create.enhanced", "ecto.migrate.enhanced"],
      "ecto.reset": ["ecto.drop", "ecto.create.enhanced", "ecto.migrate.enhanced"],
      test: ["ecto.migrate.enhanced", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"],
      # Run to check the quality of your code
      quality: ["format --check-formatted", "sobelow --config", "credo --strict"]
    ]
  end

  defp docs do
    [
      name: "AtomicFi",
      main: "introduction",
      extras: extras(),
      groups_for_extras: groups_for_extras()
    ]
  end

  defp extras do
    [
      "guides/introduction.md",
      "guides/getting-started.md",
      "guides/architecture.md",
      "guides/multi-tenancy.md",
      "guides/authentication.md",
      "guides/generators.md",
      "guides/testing.md",
      "guides/deployment.md",
      "guides/api-development.md"
    ]
  end

  defp groups_for_extras do
    [
      "Getting Started": [
        "guides/introduction.md",
        "guides/getting-started.md"
      ],
      Architecture: [
        "guides/architecture.md",
        "guides/multi-tenancy.md",
        "guides/authentication.md"
      ],
      Development: [
        "guides/generators.md",
        "guides/testing.md",
        "guides/api-development.md"
      ],
      Operations: [
        "guides/deployment.md"
      ]
    ]
  end
end
