defmodule AtomicFi.Scheduler do
  @moduledoc """
  Quantum scheduler for periodic jobs.

  Manages cron-like scheduled tasks for the application.
  Jobs are configured in config/config.exs.
  """
  use Quantum, otp_app: :atomic_fi
end
