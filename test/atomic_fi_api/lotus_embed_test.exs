defmodule AtomicFiApi.LotusEmbedTest do
  @moduledoc """
  Controller-level ports of the `lotus-embed` example app's Playwright
  e2e suite (`example-apps/lotus-embed/e2e/lotus-embed.spec.ts`).

  Only atomic-fi's own embedding code is covered — issuing the short-lived
  embed token and the `EmbedTokenAuth` gate on `/lotus`. Lotus is a
  third-party library; its dashboard, SQL editor and AI assistant are not
  exercised here. The gate's admit/expire behaviour is unit-tested in
  `test/atomic_fi_web/plugs/embed_token_auth_test.exs`.
  """
  use AtomicFiWeb.ConnCase, async: false

  setup :setup_platform_admin_api

  describe "lotus-embed.spec.ts — embed token exchange" do
    test "POST /api/lotus/embed-token issues a short-lived embed token", %{conn: conn} do
      body =
        conn
        |> post(~p"/api/lotus/embed-token")
        |> json_response(200)

      assert %{"token" => token, "expires_in" => 300} = body
      assert is_binary(token) and token != ""
    end

    test "POST /api/lotus/embed-token requires authentication" do
      assert build_conn() |> post(~p"/api/lotus/embed-token") |> json_response(401)
    end
  end

  describe "lotus-embed.spec.ts — /lotus embed-token gate" do
    test "rejects an invalid embed token (401)" do
      assert build_conn() |> get("/lotus?token=invalid") |> response(401) =~
               "Invalid embed token"
    end

    test "rejects a missing embed token (401)" do
      assert build_conn() |> get("/lotus") |> response(401) =~ "Missing embed token"
    end
  end
end
