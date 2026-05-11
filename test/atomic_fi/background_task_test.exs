defmodule AtomicFi.BackgroundTaskTest do
  use ExUnit.Case, async: false

  alias AtomicFi.BackgroundTask
  alias AtomicFi.Config

  setup do
    on_exit(fn -> Application.delete_env(:atomic_fi, :force_async_background_task) end)
    :ok
  end

  test "runs synchronously in :test by default" do
    parent = self()
    BackgroundTask.run(fn -> send(parent, {:ran, self()}) end)

    assert_received {:ran, runner_pid}
    assert runner_pid == self()
  end

  test "returns the function's return value when synchronous" do
    assert BackgroundTask.run(fn -> 42 end) == 42
  end

  test "runs asynchronously when :force_async_background_task is true" do
    Config.put(:force_async_background_task, true)
    parent = self()

    BackgroundTask.run(fn -> send(parent, {:async_ran, self()}) end)

    assert_receive {:async_ran, runner_pid}, 1_000
    assert runner_pid != self()
  end
end
