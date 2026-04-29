defmodule AtomicFi.Schema do
  @moduledoc """
  Base schema module for all Ecto schemas in the application.

  Provides common functionality including:
  - TypedEctoSchema for compile-time type checking
  - ExOpenApiUtils for automatic OpenAPI schema generation
  - UUID primary keys by default
  - Common imports and aliases

  ## Usage

      defmodule AtomicFi.SomeContext.Resource do
        use AtomicFi.Schema

        # OpenAPI annotations
        open_api_property(schema: %Schema{type: :string}, key: :name)

        open_api_schema(
          title: "Resource",
          required: [:name],
          properties: [:id, :name, :inserted_at, :updated_at]
        )

        typed_schema "resources" do
          field :name, :string

          timestamps(type: :utc_datetime)
        end

        def changeset(resource, attrs) do
          resource
          |> cast(attrs, [:name])
          |> validate_required([:name])
        end
      end

  """

  defmacro __using__(_) do
    quote do
      use TypedEctoSchema
      use ExOpenApiUtils

      # ExOpenApiUtils already imports Ecto.Changeset, no need to import again
      import Ecto.Query

      alias OpenApiSpex.Schema

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime_usec]
    end
  end
end
