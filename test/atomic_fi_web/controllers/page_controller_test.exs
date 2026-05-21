defmodule AtomicFiWeb.PageControllerTest do
  use AtomicFiWeb.ConnCase

  test "GET / renders the atomic-fi home with the example-app list", %{conn: conn} do
    body =
      conn
      |> get(~p"/")
      |> html_response(200)

    # atomic-fi branding (not the Phoenix scaffold copy)
    assert body =~ "OSS compliance platform for payments"

    # Each example app appears with both label and link href
    assert body =~ "Onboarding flow"
    assert body =~ ~s(href="/demo/onboarding-flow/")
    assert body =~ "JDM editor + copilot"
    assert body =~ ~s(href="/demo/atomic-fi-jdm-editor/")
    assert body =~ "Lotus dashboard embed"
    assert body =~ ~s(href="/demo/lotus-embed/")
  end

  test "GET /demo/<app>/ serves the static index via Plug.Static", %{conn: conn} do
    # In dev/test the build is produced by `mix server`'s vite watchers; in
    # this unit test we drop a placeholder so Plug.Static has something to
    # find. The route itself isn't declared in the router — Plug.Static
    # matches first because "demo" is in AtomicFiWeb.static_paths/0.
    placeholder = "priv/static/demo/onboarding-flow/index.html"
    File.mkdir_p!(Path.dirname(placeholder))
    File.write!(placeholder, "<h1>onboarding-flow placeholder</h1>")

    body =
      conn
      |> get("/demo/onboarding-flow/index.html")
      |> response(200)

    assert body =~ "onboarding-flow placeholder"
  end

  test "GET /health-check returns 200 with status ok", %{conn: conn} do
    conn = get(conn, ~p"/health-check")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
