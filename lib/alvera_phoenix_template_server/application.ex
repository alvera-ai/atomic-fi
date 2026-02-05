defmodule AlveraPhoenixTemplateServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      AlveraPhoenixTemplateServerWeb.Telemetry,
      # Start the encryption vault
      AlveraPhoenixTemplateServer.Vault,
      # Start the Ecto repository
      AlveraPhoenixTemplateServer.Repo,
      # Start Cachex for API session caching
      {Cachex, name: :api_session_cache},
      # Start SessionCleaner for periodic cleanup
      AlveraPhoenixTemplateServer.SessionContext.SessionCleaner,
      # Start the PubSub system
      {Phoenix.PubSub, name: AlveraPhoenixTemplateServer.PubSub},
      # Start Finch
      {Finch, name: AlveraPhoenixTemplateServer.Finch},
      # Start the Endpoint (http/https)
      AlveraPhoenixTemplateServerWeb.Endpoint
      # Start a worker by calling: AlveraPhoenixTemplateServer.Worker.start_link(arg)
      # {AlveraPhoenixTemplateServer.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AlveraPhoenixTemplateServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AlveraPhoenixTemplateServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
