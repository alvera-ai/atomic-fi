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
      |> Enum.map(fn {field, messages} ->
        %{
          detail: Enum.join(messages, ", "),
          source: %{pointer: "/#{field}"},
          title: "Invalid value"
        }
      end)

    %{errors: errors}
  end
end
