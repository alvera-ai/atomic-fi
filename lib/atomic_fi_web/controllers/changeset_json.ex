defmodule AtomicFiWeb.ChangesetJSON do
  @moduledoc """
  Renders changeset errors in JSON:API format for OpenApiSpex v2.

  Used by FallbackController to format Ecto.Changeset validation errors into a
  standard JSON:API error response structure.
  """

  @doc """
  Renders changeset errors as JSON:API error array.

  Each error includes:
  - `detail`: The error message
  - `source`: Pointer to the field that caused the error
  - `title`: Error category (always "Invalid value")

  ## Example

      %{
        errors: [
          %{
            detail: "can't be blank",
            source: %{pointer: "/name"},
            title: "Invalid value"
          }
        ]
      }
  """
  def error(%{changeset: changeset}) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        # Replace placeholders like %{count} with actual values from opts
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)
      |> Enum.flat_map(&flatten_errors/1)

    %{errors: errors}
  end

  defp flatten_errors({field, messages}, prefix \\ "") do
    pointer = "#{prefix}/#{field}"

    Enum.with_index(messages)
    |> Enum.flat_map(fn
      {msg, _idx} when is_binary(msg) ->
        [%{detail: msg, source: %{pointer: pointer}, title: "Invalid value"}]

      {nested, idx} when is_map(nested) ->
        Enum.flat_map(nested, &flatten_errors(&1, "#{pointer}/#{idx}"))
    end)
  end
end
