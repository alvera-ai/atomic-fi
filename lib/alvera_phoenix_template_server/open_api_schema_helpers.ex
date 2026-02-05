defmodule AlveraPhoenixTemplateServer.OpenApiSchemaHelpers do
  @moduledoc """
  Macros for generating OpenAPI response schemas.

  These macros reduce boilerplate when defining list response schemas that follow
  the standard `{data: [], meta: {}}` pattern.
  """

  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  @doc """
  Generates a list response schema with data array and pagination meta.

  ## Example

      deflistresponse TenantListResponse, AlveraPhoenixTemplateServer.OpenApiSchema.TenantResponse, "tenants"

  Generates a schema equivalent to:

      %{
        title: "TenantListResponse",
        type: :object,
        properties: %{
          data: %Schema{type: :array, items: %Reference{"$ref": "#/components/schemas/TenantResponse"}},
          meta: %Reference{"$ref": "#/components/schemas/PaginationMeta"}
        },
        required: [:data, :meta]
      }

  NOTE: Uses OpenApiSpex.Reference for items/meta to ensure proper casting in array context.
  """
  defmacro deflistresponse(name, item_schema, plural_name) do
    name_string = Macro.to_string(name)

    # Extract schema title from module name (e.g., AlveraPhoenixTemplateServer.OpenApiSchema.TenantResponse -> TenantResponse)
    item_schema_title = item_schema |> Macro.to_string() |> String.split(".") |> List.last()
    item_ref = "#/components/schemas/#{item_schema_title}"

    quote do
      defmodule unquote(name) do
        @moduledoc false
        require OpenApiSpex

        OpenApiSpex.schema(%{
          title: unquote(name_string),
          description: "Paginated list of #{unquote(plural_name)}",
          type: :object,
          properties: %{
            data: %Schema{
              type: :array,
              description: "List of #{unquote(plural_name)}",
              items: %Reference{"$ref": unquote(item_ref)}
            },
            meta: %Reference{"$ref": "#/components/schemas/PaginationMeta"}
          },
          required: [:data, :meta]
        })
      end
    end
  end

  @doc """
  Generates a data response schema (non-paginated, data array only).

  ## Example

      defdataresponse ServiceCategoriesDataResponse, AlveraPhoenixTemplateServer.OpenApiSchema.ServiceCategoryResponse, "service categories"
  """
  defmacro defdataresponse(name, item_schema, plural_name) do
    name_string = Macro.to_string(name)
    # Extract schema title from module name
    item_schema_title = item_schema |> Macro.to_string() |> String.split(".") |> List.last()
    item_ref = "#/components/schemas/#{item_schema_title}"

    quote do
      defmodule unquote(name) do
        @moduledoc false
        require OpenApiSpex

        OpenApiSpex.schema(%{
          title: unquote(name_string),
          description: "List of #{unquote(plural_name)} (non-paginated)",
          type: :object,
          properties: %{
            data: %Schema{
              type: :array,
              description: "List of #{unquote(plural_name)}",
              items: %Reference{"$ref": unquote(item_ref)}
            }
          },
          required: [:data]
        })
      end
    end
  end
end
