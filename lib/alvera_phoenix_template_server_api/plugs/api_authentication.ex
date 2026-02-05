defmodule AlveraPhoenixTemplateServerApi.Plugs.ApiAuthentication do
  @moduledoc """
  Validates API key from x-api-key header and loads session.

  - Validates API key on every request
  - Creates or loads cached session
  - Assigns current_api_key, api_session, and session_id to conn
  - Returns 401 if invalid or missing API key
  - Captures Cloudflare headers for audit trail
  """

  import Plug.Conn
  require Logger

  alias AlveraPhoenixTemplateServer.ApiKeyContext
  alias AlveraPhoenixTemplateServer.SessionContext.SessionManager

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "x-api-key") do
      [api_key] ->
        authenticate_and_load_session(conn, api_key)

      _ ->
        unauthorized_response(conn, "API key required. Include x-api-key header.")
    end
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
