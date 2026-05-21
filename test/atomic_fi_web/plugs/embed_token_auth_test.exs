defmodule AtomicFiWeb.Plugs.EmbedTokenAuthTest do
  @moduledoc """
  Unit-level port of the `lotus-embed` Playwright suite's embed-gate
  scenarios — the `EmbedTokenAuth` plug that guards `/lotus`.

  Companion to the controller-level ports in
  `test/atomic_fi_api/lotus_embed_test.exs`. Exercises atomic-fi's own
  embedding code only; Lotus itself is a third-party library.
  """
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias AtomicFiWeb.Plugs.EmbedTokenAuth

  defp sign(payload, opts \\ []) do
    Phoenix.Token.sign(AtomicFiWeb.Endpoint, "lotus-embed", payload, opts)
  end

  # Run a `GET /lotus<query>` through the plug, with a session fetched —
  # the `:lotus_embed` pipeline runs `:fetch_session` ahead of the plug.
  defp gate(query) do
    conn(:get, "/lotus" <> query)
    |> init_test_session(%{})
    |> fetch_query_params()
    |> EmbedTokenAuth.call(EmbedTokenAuth.init([]))
  end

  test "admits a valid embed token and assigns the lotus identity" do
    token = sign(%{user_id: "user-1", tenant_id: "tenant-1"})

    conn = gate("?token=#{URI.encode_www_form(token)}")

    refute conn.halted
    assert conn.assigns.lotus_user_id == "user-1"
    assert conn.assigns.lotus_tenant_id == "tenant-1"
  end

  test "rejects an invalid embed token with 401" do
    conn = gate("?token=not-a-real-token")

    assert conn.halted
    assert conn.status == 401
    assert conn.resp_body =~ "Invalid embed token"
  end

  test "rejects a missing embed token with 401" do
    conn = gate("")

    assert conn.halted
    assert conn.status == 401
    assert conn.resp_body =~ "Missing embed token"
  end

  test "rejects an expired embed token with 401" do
    # Signed ~17 min ago — past EmbedTokenAuth's 300s max_age.
    stale = System.system_time(:second) - 1000
    token = sign(%{user_id: "user-1", tenant_id: "tenant-1"}, signed_at: stale)

    conn = gate("?token=#{URI.encode_www_form(token)}")

    assert conn.halted
    assert conn.status == 401
    assert conn.resp_body =~ "Embed token expired"
  end
end
