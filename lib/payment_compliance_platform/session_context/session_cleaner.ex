defmodule PaymentCompliancePlatform.SessionContext.SessionCleaner do
  @moduledoc """
  GenServer that periodically cleans inactive API sessions.

  Runs cleanup every hour to remove:
  - Sessions marked as inactive
  - Sessions whose API key is inactive or deleted
  """

  use GenServer
  require Logger

  alias PaymentCompliancePlatform.SessionContext.SessionManager

  @cleanup_interval :timer.hours(1)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_cleanup()
    {:ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    Logger.info("Cleaning inactive API sessions...")

    case SessionManager.clear_expired_sessions() do
      {count, _} when count > 0 ->
        Logger.info("Cleaned #{count} inactive API sessions")

      _ ->
        :ok
    end

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
