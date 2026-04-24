defmodule PaymentCompliancePlatform.BackgroundTask do
  @moduledoc """
  Run a function in a separate process parallel to the current one. Useful
  for fire-and-forget side effects — e.g. bumping `last_used_at` on an API
  key after authentication — that should not block the caller.

      PaymentCompliancePlatform.BackgroundTask.run(fn ->
        do_some_time_intensive_stuff()
      end)

  ## Test behaviour

  In `:test`, the function is invoked synchronously so that test assertions
  observe the side effect without sleeps, and so the work doesn't outlive
  the Sandbox-owned DB connection (which would surface as a `DBConnection`
  ownership warning at teardown).

  Set `:force_async_background_task` in config if you explicitly want async
  behaviour in test (e.g. to exercise the supervision tree path).
  """

  alias PaymentCompliancePlatform.Config

  # Adjust if a background task is expected to run longer than 5 seconds.
  @shutdown_timeout_ms 5_000

  @doc """
  Runs `f` asynchronously under the task supervisor in non-test envs
  (or if `:force_async_background_task` is set). Runs synchronously in
  `:test` so assertions observe side effects without sleeps.
  """
  @spec run((-> term())) :: term()
  def run(f) when is_function(f, 0) do
    if run_async?() do
      run_supervised(f)
    else
      f.()
    end
  end

  defp run_async? do
    (Config.get(:env) != :test || Config.get(:force_async_background_task, false)) &&
      Process.whereis(__MODULE__) != nil
  end

  defp run_supervised(f) do
    Task.Supervisor.start_child(
      __MODULE__,
      fn ->
        Process.flag(:trap_exit, true)
        f.()
      end,
      restart: :transient,
      shutdown: @shutdown_timeout_ms
    )
  end
end
