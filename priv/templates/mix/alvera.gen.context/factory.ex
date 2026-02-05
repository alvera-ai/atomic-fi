defmodule <%= inspect context.base_module %>.Factory.<%= inspect schema.alias %>Factory do
  @moduledoc """
  Factory for <%= inspect schema.alias %> context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias <%= inspect schema.module %>

      def <%= schema.singular %>_factory do
        unique_suffix = String.slice(Ecto.UUID.generate(), 0, 8)

        %<%= inspect schema.alias %>{
<%= for {k, v} <- schema.params.create do %>          <%= k %>: <%= cond do
              is_binary(v) and String.starts_with?(v, "some ") -> inspect(v) <> " <> unique_suffix"
              is_binary(v) -> inspect(v)
              true -> inspect(v)
            end %>,
<% end %>          <%= String.trim_trailing(to_string(rls_field), "_id") %>: build(:<%= String.trim_trailing(to_string(rls_table), "s") %>)
        }
      end
    end
  end
end
