defmodule AtomicFiApi.Controller do
  @moduledoc """
  Shared controller functionality for all API controllers.

  This module wraps controller actions with centralized exception handling,
  eliminating the need for repetitive `rescue` blocks in each controller.

  ## Usage

  Replace `use AtomicFiWeb, :controller` with:

      use AtomicFiApi.Controller

  ## Exception Handling

  The `action/2` callback automatically handles:

  - `Ecto.NoResultsError` → 404 Not Found
  - `Ecto.StaleEntryError` → 409 Conflict

  These exceptions are converted to proper JSON error responses using
  `AtomicFiWeb.ErrorJSON`, which returns the standard error format:

      %{errors: %{detail: "Not Found"}}

  ## Example

      defmodule AtomicFiApi.TenantController do
        use AtomicFiApi.Controller
        use OpenApiSpex.ControllerSpecs

        # No need for rescue blocks!
        def show(conn, %{id: id}) do
          tenant = TenantContext.get_tenant!(conn.assigns.api_session, id)
          render(conn, :show, tenant: tenant)
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      use AtomicFiWeb, :controller

      @doc """
      Wraps all controller actions with centralized exception handling.

      This callback is invoked by Phoenix for every request before calling
      the actual controller action. It rescues common Ecto exceptions and
      converts them to proper HTTP error responses.
      """
      def action(conn, _params) do
        args = [conn, conn.params]
        apply(__MODULE__, action_name(conn), args)
      rescue
        Ecto.NoResultsError ->
          conn
          |> Plug.Conn.put_status(:not_found)
          |> Phoenix.Controller.put_view(json: AtomicFiWeb.ErrorJSON)
          |> Phoenix.Controller.render(:"404")

        Ecto.Query.CastError ->
          conn
          |> Plug.Conn.put_status(:unprocessable_entity)
          |> Phoenix.Controller.put_view(json: AtomicFiWeb.ErrorJSON)
          |> Phoenix.Controller.render(:"422")

        Ecto.StaleEntryError ->
          conn
          |> Plug.Conn.put_status(:conflict)
          |> Phoenix.Controller.put_view(json: AtomicFiWeb.ErrorJSON)
          |> Phoenix.Controller.render(:"409")
      end

      defoverridable action: 2
    end
  end
end
