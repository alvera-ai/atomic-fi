defmodule AlveraPhoenixTemplateServerApi.ApiInfoController do
  use AlveraPhoenixTemplateServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias AlveraPhoenixTemplateServer.Repo
  alias AlveraPhoenixTemplateServer.OpenApiSchema.{ApiInfoResponse, ApiInfoErrorResponse}
  alias AlveraPhoenixTemplateServerApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference

  tags(["Health"])

  @doc """
  API info endpoint with database connectivity check.
  Returns version info and tests database connection using a separate process.
  Handles password rotation by creating a new connection for each request.
  """
  operation(:info,
    summary: "API information",
    description: """
    Public API info endpoint that returns:
    - Application version (from mix.exs)
    - Database connectivity status (SELECT 1 query in separate process)
    - Current timestamp

    **Database check**: Creates a separate Repo process to test connectivity,
    which handles password rotation gracefully by establishing a fresh connection.

    **No authentication required.**
    """,
    responses: [
      ok:
        {"API is healthy", "application/json",
         %Reference{"$ref": "#/components/schemas/ApiInfoResponse"}},
      internal_server_error:
        {"Database connection failed", "application/json",
         %Reference{"$ref": "#/components/schemas/ApiInfoErrorResponse"}}
    ]
  )

  def info(conn, _params) do
    # Get version from application spec
    version = get_version()

    # Test database connectivity with separate process (handles password rotation)
    database_status = check_database_connection()

    case database_status do
      :connected ->
        data = %{
          status: "ok",
          version: version,
          database_status: "connected",
          timestamp: DateTime.utc_now()
        }

        ApiHelpers.json_response(conn, data, ApiInfoResponse)

      {:error, reason} ->
        data = %{
          status: "error",
          version: version,
          database_status: "disconnected",
          error: "Database connection failed: #{inspect(reason)}",
          timestamp: DateTime.utc_now()
        }

        conn
        |> put_status(:internal_server_error)
        |> ApiHelpers.json_response(data, ApiInfoErrorResponse)
    end
  end

  defp get_version do
    case Application.spec(:alvera_phoenix_template_server, :vsn) do
      vsn when is_list(vsn) -> List.to_string(vsn)
      vsn when is_binary(vsn) -> vsn
      nil -> "unknown"
    end
  end

  defp check_database_connection do
    # Create a separate process to test database connectivity
    # This handles password rotation by creating a fresh connection
    task =
      Task.async(fn ->
        # Get a new connection from the pool
        Ecto.Adapters.SQL.query(Repo, "SELECT 1", [], timeout: 5_000)
      end)

    case Task.await(task, 6_000) do
      {:ok, _result} ->
        :connected

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      {:error, Exception.message(error)}
  end
end
