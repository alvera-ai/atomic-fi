defmodule PaymentCompliancePlatformApi.Plugs.ApiAuthentication do
  @moduledoc """
  Authenticates requests via X-API-Key (M2M) OR Authorization: Bearer (human,
  issued by `POST /api/sessions`).

  Resolution order:
  1. `X-API-Key: <key>` — validated against `api_keys.key_hash`; session loaded
     via `SessionManager.get_or_create_session/2`. Type = `:api`.
  2. `Authorization: Bearer <token>` — verified via
     `UserContext.verify_user_session_api_token_query/1`; linked session
     loaded via `SessionManager.get_session_by_user_token_id/1`. Type = `:user`.
  3. Neither present or invalid → 401.

  Assigns on success:
  - `:api_session` — the `%Session{}` (both auth types)
  - `:session_id` — session id (both auth types)
  - `:current_api_key` — the `%ApiKey{}` (X-API-Key only)
  - `:current_user` — the `%User{}` (Bearer only)

  Also captures Cloudflare headers into session metadata for audit trail.
  """

  import Plug.Conn
  require Logger

  alias PaymentCompliancePlatform.ApiKeyContext
  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.SessionContext.Session
  alias PaymentCompliancePlatform.SessionContext.SessionManager
  alias PaymentCompliancePlatform.UserContext

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      api_key = api_key_header(conn) ->
        authenticate_and_load_session(conn, api_key)

      bearer = bearer_token(conn) ->
        authenticate_bearer(conn, bearer)

      true ->
        unauthorized_response(
          conn,
          "Credentials required. Provide x-api-key header or Authorization: Bearer <token>."
        )
    end
  end

  defp api_key_header(conn) do
    case get_req_header(conn, "x-api-key") do
      [key | _] when is_binary(key) and key != "" -> key
      _ -> nil
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] when is_binary(token) and token != "" -> token
      ["bearer " <> token | _] when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end

  defp authenticate_bearer(conn, token) do
    with {:ok, query} <- UserContext.verify_user_session_api_token_query(token),
         %{id: user_token_id} <- Repo.one(query, skip_multi_tenancy_check: true),
         %Session{} = session <- SessionManager.get_session_by_user_token_id(user_token_id),
         :ok <- check_not_expired(session) do
      conn
      |> assign(:current_user, session.user)
      |> assign(:api_session, session)
      |> assign(:session_id, session.id)
    else
      _ ->
        unauthorized_response(conn, "Invalid or expired Bearer token")
    end
  end

  defp check_not_expired(%Session{expires_at: nil}), do: :ok

  defp check_not_expired(%Session{expires_at: %DateTime{} = expires_at}) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :gt, do: :ok, else: :expired
  end

  defp authenticate_and_load_session(conn, api_key_value) do
    # Validate API key
    case ApiKeyContext.validate_api_key(api_key_value) do
      {:ok, api_key} ->
        # Get or create session with metadata (including Cloudflare headers)
        metadata = %{
          ip_address: get_client_ip(conn),
          user_agent: get_user_agent(conn),
          cloudflare_metadata: get_cloudflare_metadata(conn)
        }

        # SessionManager.get_or_create_session always returns {:ok, session}
        {:ok, api_session} = SessionManager.get_or_create_session(api_key, metadata)

        conn
        |> assign(:current_api_key, api_key)
        |> assign(:api_session, api_session)
        |> assign(:session_id, api_session.id)

      {:error, :invalid_api_key} ->
        unauthorized_response(conn, "Invalid API key")
    end
  end

  defp get_client_ip(conn) do
    # Priority: CF-Connecting-IP (Cloudflare) > X-Forwarded-For > X-Real-IP > remote_ip
    cond do
      # Cloudflare's actual client IP (most reliable)
      match?([ip | _] when is_binary(ip), get_req_header(conn, "cf-connecting-ip")) ->
        hd(get_req_header(conn, "cf-connecting-ip"))

      # X-Forwarded-For (get first IP in chain)
      match?([header | _] when is_binary(header), get_req_header(conn, "x-forwarded-for")) ->
        header = hd(get_req_header(conn, "x-forwarded-for"))
        header |> String.split(",") |> List.first() |> String.trim()

      # X-Real-IP
      match?([ip | _] when is_binary(ip), get_req_header(conn, "x-real-ip")) ->
        hd(get_req_header(conn, "x-real-ip"))

      # Fallback to remote_ip
      true ->
        to_string(:inet_parse.ntoa(conn.remote_ip))
    end
  end

  defp get_user_agent(conn) do
    case get_req_header(conn, "user-agent") do
      [ua | _] -> ua
      _ -> nil
    end
  end

  defp get_cloudflare_metadata(conn) do
    # Capture Cloudflare headers for audit trail
    %{
      "cf_ray" => get_header(conn, "cf-ray"),
      "cf_ipcountry" => get_header(conn, "cf-ipcountry"),
      "cf_visitor" => get_header(conn, "cf-visitor"),
      "x_forwarded_proto" => get_header(conn, "x-forwarded-proto"),
      "x_forwarded_for" => get_header(conn, "x-forwarded-for")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp get_header(conn, header_name) do
    case get_req_header(conn, header_name) do
      [value | _] -> value
      _ -> nil
    end
  end

  defp unauthorized_response(conn, message) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{errors: %{detail: message}})
    |> halt()
  end
end
