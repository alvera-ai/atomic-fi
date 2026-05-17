defmodule AtomicFiWeb.Plugs.EmbedTokenAuth do
  @moduledoc """
  Validates a short-lived Phoenix.Token passed as `?token=` query param.

  Used to authenticate iframe embeds (Lotus dashboard) without requiring
  the parent app to share cookies or session state.

  Flow:
  1. Authenticated client calls `POST /api/lotus/embed-token` → receives a signed token
  2. Client renders `<iframe src="/lotus?token=<token>">`
  3. This plug verifies the token, sets session assigns, and allows LiveView mount
  """

  import Plug.Conn

  @max_age 300

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.params["token"] do
      nil ->
        maybe_resume_session(conn)

      token ->
        case Phoenix.Token.verify(AtomicFiWeb.Endpoint, "lotus-embed", token, max_age: @max_age) do
          {:ok, %{user_id: user_id, tenant_id: tenant_id}} ->
            conn
            |> put_session(:lotus_user_id, user_id)
            |> put_session(:lotus_tenant_id, tenant_id)
            |> assign(:lotus_user_id, user_id)
            |> assign(:lotus_tenant_id, tenant_id)

          {:error, :expired} ->
            reject(conn, "Embed token expired")

          {:error, _reason} ->
            reject(conn, "Invalid embed token")
        end
    end
  end

  defp maybe_resume_session(conn) do
    user_id = get_session(conn, :lotus_user_id)
    tenant_id = get_session(conn, :lotus_tenant_id)

    if user_id && tenant_id do
      conn
      |> assign(:lotus_user_id, user_id)
      |> assign(:lotus_tenant_id, tenant_id)
    else
      reject(conn, "Missing embed token")
    end
  end

  defp reject(conn, message) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(401, message)
    |> halt()
  end
end
