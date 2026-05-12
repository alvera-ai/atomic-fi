defmodule AtomicFiWeb.PageControllerTest do
  use AtomicFiWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
  end

  test "GET /health-check returns 200 with status ok", %{conn: conn} do
    conn = get(conn, ~p"/health-check")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
