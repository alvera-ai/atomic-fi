defmodule AtomicFiWeb.PageControllerTest do
  use AtomicFiWeb.ConnCase

  test "GET / renders the atomic-fi home with the example-app list", %{conn: conn} do
    body =
      conn
      |> get(~p"/")
      |> html_response(200)

    # atomic-fi branding (not the Phoenix scaffold copy)
    assert body =~ "OSS compliance platform for payments"

    # Each example app appears with label + bare /demo/<app>/ href.
    # The bare path is served index.html by the demo_app SPA fallback;
    # the app's React Router (basename /demo/<app>/) then resolves it.
    assert body =~ "Onboarding flow"
    assert body =~ ~s(href="/demo/onboarding-flow/")
    assert body =~ "JDM editor + copilot"
    assert body =~ ~s(href="/demo/atomic-fi-jdm-editor/")
    assert body =~ "Lotus dashboard embed"
    assert body =~ ~s(href="/demo/lotus-embed/")
  end

  test "GET /demo/<app>/ + a deep link both serve the SPA shell", %{conn: conn} do
    # In dev/test the build is produced by `make server`'s vite
    # watchers; in this unit test we drop a placeholder so the
    # demo_app fallback has an index.html to send.
    placeholder = "priv/static/demo/onboarding-flow/index.html"
    File.mkdir_p!(Path.dirname(placeholder))
    File.write!(placeholder, "<h1>onboarding-flow placeholder</h1>")

    # bare app root
    assert conn |> get("/demo/onboarding-flow/") |> response(200) =~
             "onboarding-flow placeholder"

    # a client-side route (deep link / refresh) — no such file exists,
    # the SPA fallback still serves index.html
    assert build_conn() |> get("/demo/onboarding-flow/onboarding/abc/identity") |> response(200) =~
             "onboarding-flow placeholder"
  end

  test "GET /demo/<unknown>/ is a 404", %{conn: conn} do
    assert conn |> get("/demo/not-a-real-app/") |> response(404) =~ "Unknown demo"
  end

  test "GET /health-check returns 200 with status ok", %{conn: conn} do
    conn = get(conn, ~p"/health-check")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
