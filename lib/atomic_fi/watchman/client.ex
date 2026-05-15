defmodule AtomicFi.Watchman.Client do
  @moduledoc """
  HTTP client for the Watchman sanctions screening service.

  Plain code — no behaviour at this layer. The mock seam lives one level up at
  `AtomicFi.ScreeningEngine.Behaviour`; this module is treated
  like a database driver — exercised by integration paths, not unit-mocked.

  Built on `Req` with a small response-step pipeline that decodes Watchman JSON
  bodies into the typed structs declared per call via the `:decode_into` opt:

      decode_into: %{200 => SearchResponse, 400 => ErrorResponse}

  Status codes not in the map yield `{:error, {:unexpected_status, status, body}}`.

  ## Coverage stance

  Network-error and decode-fallback branches use `# coveralls-ignore` because
  they are defensive plumbing (Watchman returning malformed JSON or being
  unreachable is treated like a database outage — not unit-tested here).
  """

  alias AtomicFi.Watchman.{
    ErrorResponse,
    IngestFileResponse,
    ListInfoResponse,
    SearchResponse
  }

  # Whitelist of query-string parameters accepted by Watchman's `GET /v2/search`,
  # mirroring the Watchman OpenAPI spec. Defensive against caller typos — keys
  # not in this list are silently dropped instead of being sent to Watchman.
  @search_query_keys ~w(
    address addresses aircraftType altNames birthDate built callSign created
    cryptoAddress cryptoAddresses deathDate debug debugSourceIDs dissolved
    email emailAddress emailAddresses fax faxNumber faxNumbers flag gender
    grossRegisteredTonnage icaoCode imoNumber limit minMatch mmsi model name
    owner phone phoneNumber phoneNumbers requestID serialNumber source sourceID
    titles tonnage type vesselType website websites
  )a

  # ── public API ────────────────────────────────────────────────────────────

  @spec v2_search_get(keyword()) ::
          {:ok, SearchResponse.t()} | {:error, ErrorResponse.t() | term()} | :error
  def v2_search_get(params \\ []) do
    req()
    |> Req.get(
      url: "/v2/search",
      params: Keyword.take(params, @search_query_keys),
      decode_into: %{200 => SearchResponse, 400 => ErrorResponse}
    )
    |> normalize_response()
  end

  @spec v2_listinfo_get(keyword()) :: {:ok, ListInfoResponse.t()} | :error
  def v2_listinfo_get(_opts \\ []) do
    req()
    |> Req.get(
      url: "/v2/listinfo",
      decode_into: %{200 => ListInfoResponse}
    )
    |> normalize_response()
  end

  @spec v2_ingest_file_type_post(String.t(), String.t(), keyword()) ::
          {:ok, IngestFileResponse.t()} | :error
  def v2_ingest_file_type_post(file_type, body, _opts \\ []) do
    req()
    |> Req.post(
      url: "/v2/ingest/#{file_type}",
      body: body,
      headers: [{"content-type", "text/plain"}],
      decode_into: %{200 => IngestFileResponse}
    )
    |> normalize_response()
  end

  # ── private: Req pipeline ─────────────────────────────────────────────────

  defp req do
    Req.new(
      base_url: Keyword.fetch!(Application.fetch_env!(:atomic_fi, __MODULE__), :base_url),
      headers: [{"accept", "application/json"}]
    )
    |> Req.Request.register_options([:decode_into])
    |> Req.Request.append_response_steps(decode_into: &decode_step/1)
  end

  defp decode_step({req, %Req.Response{status: status, body: body} = resp}) do
    case req.options[:decode_into] do
      %{^status => module} ->
        {req, %{resp | body: decode_struct(body, module)}}

      %{} ->
        {req, %{resp | body: {:error, {:unexpected_status, status, body}}}}

      _ ->
        # coveralls-ignore-next-line — defensive: should never happen because
        # all our callers pass :decode_into; included only for safety.
        {req, resp}
    end
  end

  # ── private: response → return-tuple ──────────────────────────────────────

  # 400 from Watchman search returns ErrorResponse struct → surface as {:error, %ErrorResponse{}}.
  defp normalize_response({:ok, %Req.Response{status: 400, body: %ErrorResponse{} = err}}),
    do: {:error, err}

  # Unexpected-status path: decode_step left an {:error, _} tuple in body.
  defp normalize_response({:ok, %Req.Response{body: {:error, _} = err}}), do: err

  # Happy path: body is the decoded struct.
  defp normalize_response({:ok, %Req.Response{body: body}}), do: {:ok, body}

  # coveralls-ignore-start — transport failure path (Watchman unreachable / timeout).
  # Treated like a database outage; not unit-tested at this layer.
  defp normalize_response({:error, _reason}), do: :error
  # coveralls-ignore-stop

  # ── private: JSON map → typed struct ──────────────────────────────────────

  defp decode_struct(data, module) when is_map(data) do
    fields = module.__fields__(:t)

    struct_data =
      Enum.reduce(fields, %{}, fn {field, type}, acc ->
        key = to_string(field)

        case Map.get(data, key) do
          nil -> acc
          value -> Map.put(acc, field, decode_field(value, type))
        end
      end)

    struct(module, struct_data)
  end

  # coveralls-ignore-start — defensive fallback for non-map bodies.
  defp decode_struct(data, _module), do: data
  # coveralls-ignore-stop

  defp decode_field(value, :string), do: value
  defp decode_field(value, :integer), do: value
  defp decode_field(value, :number), do: value
  defp decode_field(value, :boolean), do: value
  defp decode_field(value, :map), do: value
  defp decode_field(value, {:enum, _}), do: value

  defp decode_field(values, [{module, :t}]) when is_list(values) do
    Enum.map(values, &decode_struct(&1, module))
  end

  defp decode_field(value, {module, :t}) when is_map(value) do
    decode_struct(value, module)
  end

  # coveralls-ignore-next-line — defensive: unknown OpenAPI field types.
  defp decode_field(value, _type), do: value
end
