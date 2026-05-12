defmodule AtomicFi.ApplicationTest do
  use ExUnit.Case, async: true

  test "config_change/3 forwards to Endpoint.config_change/2" do
    assert :ok = AtomicFi.Application.config_change([{:atomic_fi, :foo, []}], %{}, [])
  end
end
