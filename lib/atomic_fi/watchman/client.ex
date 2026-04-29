defmodule AtomicFi.Watchman.Client do
  @moduledoc """
  HTTP client for Watchman sanctions screening service using Req.

  This module implements the callback expected by oapi_generator's
  generated Operations module.

  ## Configuration

      # config/runtime.exs
      config :atomic_fi, :watchman_base_url, System.get_env("WATCHMAN_URL")

  ## Usage

      alias AtomicFi.Watchman.Operations

      # Search for entities
      {:ok, response} = Operations.v2_search_get(name: "Vladimir Putin", limit: 5)
      response.entities  # => [%Entity{name: "Vladimir Vladimirovich PUTIN", ...}]

      # Get list info
      {:ok, info} = Operations.v2_listinfo_get()
      info.lists  # => %{"us_ofac" => 18598, "us_csl" => 6682, ...}
  """

  alias AtomicFi.Config

  @doc """
  Execute an API request. Called by the generated Operations module.
  """
  @spec request(map()) :: {:ok, struct()} | {:error, struct() | term()}
  def request(%{url: url, method: method} = operation) do
    req = build_request()

    request_opts =
      [url: url, method: method]
      |> maybe_add_query(operation)
      |> maybe_add_body(operation)

    case Req.request(req, request_opts) do
      {:ok, %{status: status, body: body}} ->
        decode_response(status, body, operation)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_request do
    opts = [
      base_url: base_url(),
      headers: [{"accept", "application/json"}]
    ]

    # Use real HTTP client even in test environment to hit local Watchman
    Req.new(opts)
  end

  defp maybe_add_query(opts, %{query: query}) when query != [] do
    Keyword.put(opts, :params, query)
  end

  defp maybe_add_query(opts, _operation), do: opts

  defp maybe_add_body(opts, %{body: body}) when not is_nil(body) do
    Keyword.put(opts, :body, body)
  end

  defp maybe_add_body(opts, _operation), do: opts

  defp decode_response(status, body, %{response: response_specs}) do
    case find_response_spec(status, response_specs) do
      {_status, {module, :t}} ->
        {:ok, decode_struct(body, module)}

      {_status, :null} ->
        {:ok, body}

      nil ->
        {:error, {:unexpected_status, status, body}}
    end
  end

  defp find_response_spec(status, specs) do
    Enum.find(specs, fn
      {^status, _} -> true
      {:default, _} -> true
      _ -> false
    end)
  end

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

  defp decode_struct(data, _module), do: data

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

  defp decode_field(value, _type), do: value

  defp base_url do
    Config.fetch!(:watchman_base_url)
  end
end
