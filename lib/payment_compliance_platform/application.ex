defmodule PaymentCompliancePlatform.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize BlocklistCache ETS table before supervision tree
    PaymentCompliancePlatform.DecisionContext.BlocklistCache.init()

    children = [
      # Start the Telemetry supervisor
      PaymentCompliancePlatformWeb.Telemetry,
      # Start the encryption vault
      PaymentCompliancePlatform.Vault,
      # Start the Ecto repository
      PaymentCompliancePlatform.Repo,
      # Start Cachex for API session caching
      {Cachex, name: :api_session_cache},
      # Start SessionCleaner for periodic cleanup
      PaymentCompliancePlatform.SessionContext.SessionCleaner,
      # Start Quantum scheduler for periodic jobs (blocklist cache refresh)
      PaymentCompliancePlatform.Scheduler,
      # Start the PubSub system
      {Phoenix.PubSub, name: PaymentCompliancePlatform.PubSub},
      # Start Finch
      {Finch, name: PaymentCompliancePlatform.Finch},
      # Start the Endpoint (http/https)
      PaymentCompliancePlatformWeb.Endpoint
      # Start a worker by calling: PaymentCompliancePlatform.Worker.start_link(arg)
      # {PaymentCompliancePlatform.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PaymentCompliancePlatform.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PaymentCompliancePlatformWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
