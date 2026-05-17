defmodule AtomicFi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize BlocklistCache ETS table before supervision tree
    AtomicFi.BlocklistContext.BlocklistCache.init()

    children = [
      # Start the Telemetry supervisor
      AtomicFiWeb.Telemetry,
      # Start the encryption vault
      AtomicFi.Vault,
      # Start the Ecto repositories
      AtomicFi.Repo,
      AtomicFi.LotusRepo,
      # Start the BackgroundTask supervisor for fire-and-forget side effects
      {Task.Supervisor, name: AtomicFi.BackgroundTask},
      # Start Cachex for API session caching
      {Cachex, name: :api_session_cache},
      # Start SessionCleaner for periodic cleanup
      AtomicFi.SessionContext.SessionCleaner,
      # Start Quantum scheduler for periodic jobs (blocklist cache refresh)
      AtomicFi.Scheduler,
      # Start the PubSub system
      {Phoenix.PubSub, name: AtomicFi.PubSub},
      # Start Finch
      {Finch, name: AtomicFi.Finch},
      # Start Oban for background job processing (compliance screening)
      {Oban, Application.fetch_env!(:atomic_fi, Oban)},
      # Start the Endpoint (http/https)
      AtomicFiWeb.Endpoint
      # Start a worker by calling: AtomicFi.Worker.start_link(arg)
      # {AtomicFi.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AtomicFi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AtomicFiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
