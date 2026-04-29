defmodule AtomicFiApi.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use Phoenix.Controller, formats: [:json]

  import Phoenix.Controller
  import Plug.Conn

  # This clause handles errors returned by Ecto's insert/update/delete.
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: AtomicFiWeb.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(
      html: AtomicFiWeb.ErrorHTML,
      json: AtomicFiWeb.ErrorJSON
    )
    |> render(:"401")
  end

  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> put_view(
      html: AtomicFiWeb.ErrorHTML,
      json: AtomicFiWeb.ErrorJSON
    )
    |> render(:"403")
  end

  # This clause is an example of how to handle resources that cannot be found.
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(
      html: AtomicFiWeb.ErrorHTML,
      json: AtomicFiWeb.ErrorJSON
    )
    |> render(:"404")
  end

  # Handle Ecto.NoResultsError (raised by Repo.get!/2, Repo.one!/1, etc.)
  def call(conn, %Ecto.NoResultsError{}) do
    conn
    |> put_status(:not_found)
    |> put_view(
      html: AtomicFiWeb.ErrorHTML,
      json: AtomicFiWeb.ErrorJSON
    )
    |> render(:"404")
  end

  # Handle Flop validation errors (server-side pagination/filtering errors)
  def call(conn, {:error, %Flop.Meta{errors: errors}}) when is_list(errors) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{
      error: "Internal server error",
      message: "Pagination or filtering configuration error",
      details: %{flop_errors: inspect(errors)}
    })
  end

  # Catch-all for unknown error atoms
  def call(conn, {:error, reason}) when is_atom(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: "Processing error",
      message: "#{reason}"
    })
  end
end
