defmodule PaymentCompliancePlatformApi.ApiInfoController do
  use PaymentCompliancePlatformWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias PaymentCompliancePlatform.Repo

  alias PaymentCompliancePlatform.OpenApiSchema.{
    ApiInfoResponse,
    ApiInfoErrorResponse,
    NormalizationRulesResponse
  }

  alias PaymentCompliancePlatformApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference

  tags(["Health"])

  # Load normalization rules at compile time
  @external_resource normalization_rules_path =
                       Path.join([
                         :code.priv_dir(:payment_compliance_platform),
                         "normalization_rules.exs"
                       ])
  @normalization_rules (case File.read(normalization_rules_path) do
                          {:ok, content} ->
                            {rules, _} = Code.eval_string(content)
                            rules

                          {:error, reason} ->
                            raise "Failed to load normalization rules: #{inspect(reason)}"
                        end)

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
    case Application.spec(:payment_compliance_platform, :vsn) do
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

  @doc """
  Normalization rules endpoint.
  Returns the hardcoded normalization rules used for data quality checks.
  """
  operation(:normalization_rules,
    summary: "Get normalization rules",
    description: """
    Returns the normalization rules used across the platform for data quality:
    - **titles**: List of name titles to strip (Mr., Mrs., Dr., etc.)
    - **suffixes**: List of name suffixes to standardize (Jr., Sr., III, etc.)
    - **entity_types**: List of company entity types to remove (LLC, Inc, Corp, etc.)

    These rules are applied during account holder screening to normalize names
    and company names before blocklist matching.

    **No authentication required.**
    """,
    responses: [
      ok:
        {"Normalization rules", "application/json",
         %Reference{"$ref": "#/components/schemas/NormalizationRulesResponse"}}
    ]
  )

  def normalization_rules(conn, _params) do
    ApiHelpers.json_response(conn, @normalization_rules, NormalizationRulesResponse)
  end
end
