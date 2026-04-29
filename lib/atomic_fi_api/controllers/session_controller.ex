defmodule AtomicFiApi.SessionController do
  @moduledoc """
  Human Bearer authentication endpoints.

  * `POST /api/sessions` — public. Exchange `{email, password, tenant_slug}`
    for a Bearer token. Use on subsequent requests as
    `Authorization: Bearer <bearer>`.
  * `GET /api/sessions/verify` — authenticated (X-API-Key or Bearer).
    "Who am I" — returns the resolved tenant, role, and identity.
  * `DELETE /api/sessions` — authenticated (Bearer only). Revokes the
    current Bearer session.
  """
  use AtomicFiApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.OpenApiSchema
  alias AtomicFi.OpenApiSchema.SessionRequest
  alias AtomicFi.OpenApiSchema.SessionResponse
  alias AtomicFi.SessionContext
  alias AtomicFi.SessionContext.Session, as: SessionRecord
  alias AtomicFi.SessionContext.SessionManager
  alias AtomicFiApi.Helpers.ApiHelpers

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback AtomicFiApi.FallbackController

  tags(["Auth"])

  # ── POST /api/sessions ─────────────────────────────────────────────

  operation(:create,
    summary: "Create a Bearer session (human auth)",
    description: """
    Exchange user credentials for a Bearer token. Pass the returned `bearer`
    as `Authorization: Bearer <bearer>` on subsequent requests. Optional
    `expires_in` (seconds) controls duration (default 86400, range 60..2592000).
    """,
    request_body:
      {"User credentials", "application/json", SessionRequest.schema(), required: true},
    responses: [
      created: {"Session created", "application/json", SessionResponse},
      unauthorized:
        {"Invalid credentials or tenant", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def create(%{body_params: %SessionRequest{} = request} = conn, _params) do
    with {:ok, session} <- SessionContext.sign_in(request, request_metadata(conn)) do
      conn
      |> put_status(:created)
      |> ApiHelpers.json_response(session, SessionResponse)
    end
  end

  # ── GET /api/sessions/verify ───────────────────────────────────────

  operation(:verify,
    summary: "Verify current session",
    description:
      "Returns the current session's tenant, role, and identity. Accepts either X-API-Key or Authorization: Bearer.",
    responses: [
      ok: {"Session details", "application/json", SessionResponse},
      unauthorized:
        {"Invalid or missing credentials", "application/json", OpenApiSchema.ErrorResponse}
    ]
  )

  def verify(%{assigns: %{api_session: %SessionRecord{} = session}} = conn, _params) do
    conn
    |> put_status(:ok)
    |> ApiHelpers.json_response(session, SessionResponse)
  end

  # ── DELETE /api/sessions ───────────────────────────────────────────

  operation(:delete,
    summary: "Revoke current Bearer session",
    description:
      "Revokes a Bearer session. Does not apply to X-API-Key sessions (rotate the API key instead).",
    responses: [
      no_content: "Session revoked",
      unprocessable_entity:
        {"Non-Bearer session cannot be revoked here", "application/json",
         OpenApiSchema.ErrorResponse}
    ]
  )

  def delete(
        %{assigns: %{api_session: %SessionRecord{user_token_id: user_token_id} = session}} = conn,
        _params
      )
      when is_binary(user_token_id) do
    :ok = SessionManager.revoke_bearer_session(session)
    send_resp(conn, :no_content, "")
  end

  def delete(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> Phoenix.Controller.json(%{
      errors: %{detail: "Only Bearer sessions can be revoked via this endpoint"}
    })
  end

  defp request_metadata(conn) do
    %{
      ip_address: conn.remote_ip |> :inet_parse.ntoa() |> to_string(),
      user_agent: user_agent(conn)
    }
  end

  defp user_agent(conn) do
    case get_req_header(conn, "user-agent") do
      [ua | _] -> ua
      _ -> nil
    end
  end
end
