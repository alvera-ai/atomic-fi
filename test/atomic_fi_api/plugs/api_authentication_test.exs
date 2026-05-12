defmodule AtomicFiApi.Plugs.ApiAuthenticationTest do
  use AtomicFiWeb.ConnCase, async: false

  alias AtomicFiApi.Plugs.ApiAuthentication

  describe "call/2 — credentials required" do
    test "returns 401 with no auth header", %{conn: conn} do
      conn = ApiAuthentication.call(conn, [])
      assert conn.status == 401
      assert conn.halted
      response = Jason.decode!(conn.resp_body)
      assert response["errors"]["detail"] =~ "Credentials required"
    end

    test "returns 401 with invalid x-api-key", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.put_req_header("x-api-key", "definitely-not-a-real-key")
        |> ApiAuthentication.call([])

      assert conn.status == 401
      response = Jason.decode!(conn.resp_body)
      assert response["errors"]["detail"] == "Invalid API key"
    end

    test "returns 401 with invalid Bearer token", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", "Bearer not-a-valid-token")
        |> ApiAuthentication.call([])

      assert conn.status == 401
      response = Jason.decode!(conn.resp_body)
      assert response["errors"]["detail"] =~ "Invalid or expired Bearer token"
    end

    test "lowercase 'bearer' prefix is also accepted (still 401 for bad token)", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", "bearer xxx")
        |> ApiAuthentication.call([])

      assert conn.status == 401
    end

    test "empty x-api-key header value falls through to 401", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.put_req_header("x-api-key", "")
        |> ApiAuthentication.call([])

      assert conn.status == 401
      assert Jason.decode!(conn.resp_body)["errors"]["detail"] =~ "Credentials required"
    end
  end

  describe "call/2 — Cloudflare header capture (via successful X-API-Key auth)" do
    setup :setup_platform_admin_api

    test "succeeds with cf-connecting-ip + cloudflare headers", %{conn: conn} do
      [api_key] = Plug.Conn.get_req_header(conn, "x-api-key")

      conn =
        build_conn()
        |> Plug.Conn.put_req_header("x-api-key", api_key)
        |> Plug.Conn.put_req_header("cf-connecting-ip", "1.2.3.4")
        |> Plug.Conn.put_req_header("cf-ray", "abc123")
        |> Plug.Conn.put_req_header("cf-ipcountry", "US")
        |> Plug.Conn.put_req_header("x-forwarded-proto", "https")
        |> Plug.Conn.put_req_header("user-agent", "test-agent")
        |> ApiAuthentication.call([])

      refute conn.halted
      assert conn.assigns.api_session
      assert conn.assigns.current_api_key
      assert conn.assigns.session_id
    end

    test "exercises the x-forwarded-for IP-resolution branch", %{conn: conn} do
      [api_key] = Plug.Conn.get_req_header(conn, "x-api-key")

      conn =
        build_conn()
        |> Plug.Conn.put_req_header("x-api-key", api_key)
        |> Plug.Conn.put_req_header("x-forwarded-for", "9.9.9.9, 10.0.0.1")
        |> ApiAuthentication.call([])

      refute conn.halted
    end

    test "exercises the x-real-ip IP-resolution branch", %{conn: conn} do
      [api_key] = Plug.Conn.get_req_header(conn, "x-api-key")

      conn =
        build_conn()
        |> Plug.Conn.put_req_header("x-api-key", api_key)
        |> Plug.Conn.put_req_header("x-real-ip", "8.8.8.8")
        |> ApiAuthentication.call([])

      refute conn.halted
    end
  end
end
