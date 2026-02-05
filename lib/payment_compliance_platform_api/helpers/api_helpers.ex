defmodule PaymentCompliancePlatformApi.Helpers.ApiHelpers do
  @moduledoc """
  Helper functions for consistent API response formatting and validation.

  Provides utilities for:
  - Converting single resources to API maps using ExOpenApiUtils.Mapper
  - Wrapping paginated lists in `{"data": [...], "meta": {...}}`
  - Parsing Flop pagination parameters from query params
  - Response validation against OpenAPI schemas using OpenApiSpex.cast_and_validate

  ## Response Formats

  Following OpenAPI best practices:
  - Single resources: returned directly as the object (matches schema e.g. TenantResponse)
  - List responses: wrapped in `{data: [...], meta: {...}}` (matches schema e.g. TenantListResponse)

  ## Response Validation

  Use `json_response/3` to send JSON responses with optional schema validation:

      conn
      |> put_status(:ok)
      |> json_response(data, MyResponse)  # Validates against MyResponse schema

  This validates that the response matches the OpenAPI schema before sending,
  catching schema mismatches during development and testing.
  """

  alias Phoenix.Controller

  require Logger

  # Cache the OpenAPI spec at compile time to avoid recalculating on every request
  # resolve_schema_modules/1 ensures module references in oneOf/allOf are resolved
  @openapi_spec OpenApiSpex.resolve_schema_modules(PaymentCompliancePlatformApi.ApiSpec.spec())

  @typedoc "OpenAPI schema module that implements `schema/0`"
  @type response_schema :: module()

  @typedoc "Pagination metadata map"
  @type pagination_meta_map :: %{
          page: non_neg_integer(),
          page_size: pos_integer(),
          total_count: non_neg_integer(),
          total_pages: non_neg_integer()
        }

  @typedoc "Paginated response format"
  @type paginated_response :: %{data: [map()], meta: pagination_meta_map()}

  @doc """
  Sends a JSON response with OpenAPI schema casting and validation.

  Converts the data to a map, casts against the schema (filtering to schema-defined
  fields only), and returns the cast result as JSON.

  ## Examples

      conn |> put_status(:ok) |> json_response(data, TenantResponse)
  """
  @spec json_response(Plug.Conn.t(), map() | struct(), response_schema()) :: Plug.Conn.t()
  def json_response(conn, data, response_schema) do
    api_data = to_api_map(data, response_schema)
    Controller.json(conn, api_data)
  end

  @doc """
  Sends a paginated JSON response with OpenAPI schema validation.

  Wraps resources in `{data: [...], meta: {...}}` format and validates
  the entire response against the provided list response schema.

  ## Examples

      conn
      |> put_status(:ok)
      |> json_paginated_response(resources, meta, TenantListResponse)
  """
  @spec json_paginated_response(Plug.Conn.t(), [struct()], Flop.Meta.t(), module()) ::
          Plug.Conn.t()
  def json_paginated_response(conn, resources, %Flop.Meta{} = meta, response_schema) do
    # Map each resource, then cast the whole response against the list schema
    # The list schema will recursively cast items in the data array
    response = %{
      data: Enum.map(resources, &ExOpenApiUtils.Mapper.to_map/1),
      meta: pagination_meta(meta)
    }

    validated_response = cast_to_schema(response, response_schema)
    Controller.json(conn, validated_response)
  end

  @doc """
  Converts Flop.Meta to a standard pagination metadata map.
  """
  @spec pagination_meta(Flop.Meta.t()) :: pagination_meta_map()
  def pagination_meta(%Flop.Meta{} = meta) do
    %{
      page: meta.current_page,
      page_size: meta.page_size,
      total_count: meta.total_count,
      total_pages: meta.total_pages
    }
  end

  @doc """
  Converts a struct or map to an API-friendly map and casts against the schema.

  1. Uses ExOpenApiUtils.Mapper.to_map/1 to convert struct to map
     (Money, Time, Atom conversions handled by protocol implementations)
  2. Casts against schema - returns only schema-defined fields
  """
  @spec to_api_map(struct() | map(), response_schema()) :: map()
  def to_api_map(%_{} = struct, response_schema) do
    struct
    |> ExOpenApiUtils.Mapper.to_map()
    |> cast_to_schema(response_schema)
  end

  def to_api_map(map, response_schema) when is_map(map) do
    cast_to_schema(map, response_schema)
  end

  # Cast data against schema - returns only schema-defined fields
  defp cast_to_schema(data, response_schema) do
    schema = response_schema.schema()

    case OpenApiSpex.cast_value(data, schema, @openapi_spec) do
      {:ok, validated} ->
        validated

      {:error, errors} ->
        error_message = """
        OpenAPI response validation failed for schema #{inspect(response_schema)}
        Errors: #{inspect(errors)}
        Data: #{inspect(data, limit: 5, pretty: true)}
        """

        Logger.error(error_message)
        raise error_message
    end
  end

  @doc """
  Parses Flop pagination parameters from Phoenix query params.

  Converts string keys to atoms and handles type conversion.

  ## Examples

      iex> parse_flop_params(%{"page" => "1", "page_size" => "20", "order_by" => "name"})
      %{page: 1, page_size: 20, order_by: [:name]}
  """
  @spec parse_flop_params(map()) :: map()
  def parse_flop_params(params) when is_map(params) do
    # Handle both atom and string keys (test vs production)
    parsed =
      Enum.reduce(params, %{}, fn {key, value}, acc ->
        # Normalize key to string for comparison
        str_key = if is_atom(key), do: Atom.to_string(key), else: key

        case str_key do
          "page" -> Map.put(acc, :page, parse_integer(value))
          "page_size" -> Map.put(acc, :page_size, parse_integer(value))
          "order_by" -> Map.put(acc, :order_by, parse_order_by(value))
          "order_directions" -> Map.put(acc, :order_directions, parse_order_directions(value))
          "filters" -> Map.put(acc, :filters, value)
          _ -> acc
        end
      end)

    # Set default order_directions if order_by is provided but order_directions is not
    if Map.has_key?(parsed, :order_by) && !Map.has_key?(parsed, :order_directions) do
      # Default to :asc for all order_by fields
      order_by_count = length(parsed[:order_by] || [])
      Map.put(parsed, :order_directions, List.duplicate(:asc, order_by_count))
    else
      parsed
    end
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_integer(_), do: nil

  @doc false
  # Converts order_by string to list of atoms for Flop
  defp parse_order_by(value) when is_binary(value) do
    # Convert "name" to [:name]
    [String.to_atom(value)]
  end

  defp parse_order_by(value) when is_list(value) do
    # Already a list, convert strings to atoms
    Enum.map(value, fn
      v when is_binary(v) -> String.to_atom(v)
      v -> v
    end)
  end

  defp parse_order_by(_), do: nil

  @doc false
  # Converts order_directions string to list of atoms for Flop
  defp parse_order_directions(value) when is_binary(value) do
    # Convert "asc" or "desc" to [:asc] or [:desc]
    [String.to_atom(value)]
  end

  defp parse_order_directions(value) when is_list(value) do
    # Already a list, convert strings to atoms
    Enum.map(value, fn
      v when is_binary(v) -> String.to_atom(v)
      v -> v
    end)
  end

  defp parse_order_directions(_), do: nil
end
