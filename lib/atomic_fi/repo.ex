defmodule AtomicFi.Repo do
  @moduledoc """
  Main repository for database operations with multi-tenancy support.

  Uses row-level security (RLS) to ensure tenant isolation by deriving scope
  from session.

  ## Multi-Tenancy

  - Automatically derives scope from `session.tenant_id` when `session:` option is passed
  - Enforces tenant isolation at the database level
  - RLS fields are configurable via `config.exs`
  - Default: tenant_id

  ## Examples

      # Query with session-based scope (required)
      Repo.all(User, session: current_session)

      # System-level query (bypasses tenancy)
      Repo.all(Tenant, skip_multi_tenancy_check: true)

  ## Session Structure

      session = %Session{
        tenant_id: "...",
        role_id: "...",
        ...
      }

  ## Configuration

  Configure RLS fields in `config/config.exs`:

      config :atomic_fi,
        rls_fields: [:tenant_id],
        rls_primary_field: :tenant_id
  """
  use Ecto.Repo,
    otp_app: :atomic_fi,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query
  require Logger

  alias AtomicFi.RoleContext.RoleConstants
  alias AtomicFi.SessionContext.Session

  @rls_hierarchy Application.compile_env!(:atomic_fi, :rls_hierarchy)

  @impl true
  def prepare_query(operation, query, opts) do
    prefix = query.prefix || Map.get(query, :from, %{prefix: nil}).prefix
    prefix = prefix || opts[:prefix]

    cond do
      # Skip multi-tenancy for system operations
      opts[:skip_multi_tenancy_check] || opts[:schema_migration] ->
        {query, opts}

      # Skip multi-tenancy for Oban jobs (if using Oban)
      prefix == "oban" ->
        {query, opts}

      # Skip multi-tenancy for delete_all operations
      operation == :delete_all ->
        {query, opts}

      # Apply session-based multi-tenancy scope
      session = opts[:session] ->
        apply_session_scope(query, session, opts)

      # All other operations require session scope
      true ->
        Logger.error(
          operation: operation,
          opts: opts,
          error: "expected session or skip_multi_tenancy_check to be set",
          query: query,
          prefix: prefix
        )

        raise "expected session or skip_multi_tenancy_check to be set"
    end
  end

  # Applies multi-tenancy scope from session.
  #
  # Supports both:
  # - Session struct: Uses session.tenant_id directly (new pattern)
  # - User struct: Uses user.current_role.tenant_id (legacy pattern for backward compat)
  #
  # Checks RLS fields in priority order from config.
  # Only applies a filter if the schema actually has that field.
  #
  # Virtual field pattern: Parent entities use virtual fields (source: :id)
  #   - Tenant schema: Has virtual tenant_id field (source: :id)
  defp apply_session_scope(query, session, opts) do
    # Platform admin bypass: Check if session has a reserved role (root, platform_admin)
    # Assumes session.role is preloaded by get_session!
    cond do
      # Skip RLS for platform admin roles
      platform_admin?(session) ->
        {query, opts}

      # Apply normal RLS filtering
      true ->
        role = extract_role_scope(session)
        schema_module = get_schema_from_query(query)

        # Target schema filtering for preloads
        # If opts[:target_schemas] is provided (list of modules), RLS only applies to those schemas
        # Empty list [] means bypass RLS for all schemas
        cond do
          opts[:target_schemas] == [] ->
            {query, opts}

          is_list(opts[:target_schemas]) and schema_module not in opts[:target_schemas] ->
            {query, opts}

          true ->
            apply_rls_filter(query, role, schema_module, @rls_hierarchy, opts)
        end
    end
  end

  # Check if session has platform admin role (bypasses RLS)
  # Requires session.role to be preloaded - raises if not
  defp platform_admin?(%Session{role: %{name: role_name}}) when is_binary(role_name) do
    RoleConstants.reserved?(role_name)
  end

  defp platform_admin?(%Session{role: %Ecto.Association.NotLoaded{}}) do
    raise """
    Session role must be preloaded to check for platform admin bypass.
    Ensure SessionContext.get_session!/2 preloads the :role association.
    """
  end

  defp platform_admin?(%Session{role: nil}) do
    raise "Session must have an associated role for RLS checks"
  end

  # Non-Session structs (legacy User pattern) - no platform admin bypass
  defp platform_admin?(_), do: false

  # Extract role scope from Session or User struct
  defp extract_role_scope(%{__struct__: Session} = session) do
    %{tenant_id: session.tenant_id}
  end

  defp extract_role_scope(session) do
    # Legacy pattern: User struct has current_role with tenant_id
    atomize_keys(session.current_role || %{})
  end

  # Apply RLS filter based on priority order
  # Security: Always filter by RLS fields present in session
  # If schema doesn't have the field, query will fail (correct - prevents info leak)
  defp apply_rls_filter(query, role, schema_module, rls_hierarchy, opts) do
    # Find first hierarchy entry where session has the field
    # Don't check if schema has field - let query fail if missing (security)
    rls_entry =
      Enum.find(rls_hierarchy, fn %{field: field} ->
        Map.has_key?(role, field)
      end)

    case rls_entry do
      # Found matching RLS entry - apply filter
      %{field: field} ->
        {where(query, ^[{field, Map.get(role, field)}]), opts}

      # No matching RLS entry - session missing required fields
      nil ->
        rls_fields = Enum.map(rls_hierarchy, & &1.field)

        Logger.error(
          session_role: role,
          schema: schema_module,
          rls_fields: rls_fields,
          error: "session must have at least one RLS field"
        )

        raise "session must have at least one RLS field: #{inspect(rls_fields)}"
    end
  end

  # Extract schema module from query
  defp get_schema_from_query(%Ecto.Query{from: %{source: {_table, module}}}), do: module
  defp get_schema_from_query(_), do: nil

  # Atomize map keys for consistent access
  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      {key, value} -> {key, value}
    end)
  rescue
    ArgumentError -> map
  end

  defp atomize_keys(value), do: value
end
