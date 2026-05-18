defmodule AtomicFiApi.LotusEmbedController do
  @moduledoc """
  Issues short-lived embed tokens for the Lotus dashboard iframe.

  `POST /api/lotus/embed-token` (authenticated) → returns a Phoenix.Token
  that the client passes as `?token=` when loading the iframe.
  """

  use AtomicFiApi.Controller

  alias AtomicFi.SessionContext.Session

  @token_ttl 300

  def create(%{assigns: %{api_session: %Session{} = session}} = conn, _params) do
    payload = %{
      user_id: session.user_id || session.api_key_id,
      tenant_id: session.tenant_id
    }

    token = Phoenix.Token.sign(AtomicFiWeb.Endpoint, "lotus-embed", payload)

    json(conn, %{token: token, expires_in: @token_ttl})
  end
end
