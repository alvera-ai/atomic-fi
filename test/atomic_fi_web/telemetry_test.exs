defmodule AtomicFiWeb.TelemetryTest do
  use ExUnit.Case, async: true

  test "metrics/0 returns a non-empty list of telemetry metrics" do
    metrics = AtomicFiWeb.Telemetry.metrics()
    assert is_list(metrics)
    assert length(metrics) > 0
  end
end
