defmodule AtomicFiWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use AtomicFiWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint AtomicFiWeb.Endpoint

      use AtomicFiWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import AtomicFiWeb.ConnCase
      import AtomicFi.Factory
    end
  end

  setup tags do
    AtomicFi.DataCase.setup_sandbox(tags)
    AtomicFi.DataCase.setup_screening_engine_mock(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Initialize blocklist cache for a tenant.

  Call this helper before tests that perform screening operations
  to ensure the cache is initialized and prevent uninitialized cache exceptions.

  ## Examples

      test "POST /api/onboarding/screen", %{conn: conn} do
        init_blocklist_cache()  # Initializes platform tenant cache

        request_body = %{name: "Test", type: "individual", ...}
        conn = post(conn, ~p"/api/onboarding/screen", request_body)
        assert json_response(conn, 200)
      end

  """
  def init_blocklist_cache do
    alias AtomicFi.{Repo}
    alias AtomicFi.TenantContext.Tenant
    import Ecto.Query

    platform_tenant =
      from(t in Tenant, where: t.tenant_type == :platform)
      |> Repo.one!(skip_multi_tenancy_check: true)

    AtomicFi.DecisionContext.BlocklistCache.refresh_tenant_cache(platform_tenant.id)
  end

  @doc """
  Initialize blocklist cache for a specific tenant.

  Use this when testing with custom tenants (not the platform tenant).

  ## Examples

      test "screens with custom tenant" do
        tenant = insert_tenant_with_cache()
        init_blocklist_cache(tenant.id)
        # ... perform screening ...
      end

  """
  def init_blocklist_cache(tenant_id) do
    AtomicFi.DecisionContext.BlocklistCache.refresh_tenant_cache(tenant_id)
  end

  @doc """
  Seed demo blocklist entries for platform tenant and initialize cache.

  Creates the same blocklist entries as seeds.exs for testing purposes.
  """
  def seed_blocklist_for_platform_tenant do
    alias AtomicFi.{Repo}
    alias AtomicFi.TenantContext.Tenant
    alias AtomicFi.BlocklistContext.BlocklistEntry
    import Ecto.Query

    platform_tenant =
      from(t in Tenant, where: t.tenant_type == :platform)
      |> Repo.one!(skip_multi_tenancy_check: true)

    demo_entries = [
      # Exact matches - First names
      %{
        scope: :first_name,
        entry_type: :exact,
        term: "john",
        reason: "Demo blocked",
        active: true
      },
      %{
        scope: :first_name,
        entry_type: :exact,
        term: "test",
        reason: "Demo blocked",
        active: true
      },
      # Exact matches - Last names
      %{scope: :last_name, entry_type: :exact, term: "doe", reason: "Demo blocked", active: true},
      # Exact matches - Company names
      %{
        scope: :company_name,
        entry_type: :exact,
        term: "acme",
        reason: "Demo blocked",
        active: true
      },
      # Regex patterns (case-insensitive for normalized names)
      %{
        scope: :first_name,
        entry_type: :regex,
        term: "(?i)^user\\d+$",
        reason: "User + number",
        active: true
      },
      %{
        scope: :company_name,
        entry_type: :regex,
        term: "^(ZZZ|XXX|AAA)\\s",
        reason: "Placeholder",
        active: true
      }
    ]

    Enum.each(demo_entries, fn entry_attrs ->
      %BlocklistEntry{}
      |> BlocklistEntry.changeset(Map.put(entry_attrs, :tenant_id, platform_tenant.id))
      |> Repo.insert!(skip_multi_tenancy_check: true)
    end)

    AtomicFi.DecisionContext.BlocklistCache.refresh_tenant_cache(platform_tenant.id)
  end

  @doc """
  Setup helper for API tests that need platform_admin_api authentication.

  Loads the platform_admin_api key created by test_migrations and creates
  an authenticated connection with the associated session.

      setup :setup_platform_admin_api

  It stores the authenticated connection, api_key, session, and platform_tenant
  in the test context.
  """
  def setup_platform_admin_api(%{conn: conn}) do
    alias AtomicFi.Repo
    alias AtomicFi.ApiKeyContext.ApiKey
    alias AtomicFi.SessionContext.Session
    alias AtomicFi.RoleContext.Role
    alias AtomicFi.TenantContext.Tenant
    alias AtomicFi.Vault
    import Ecto.Query

    # Get platform tenant
    platform_tenant =
      from(t in Tenant, where: t.tenant_type == :platform)
      |> Repo.one!(skip_multi_tenancy_check: true)

    # Get platform_admin_api role
    platform_admin_api_role =
      from(r in Role,
        where: r.name == "platform_admin_api" and r.tenant_id == ^platform_tenant.id
      )
      |> Repo.one!(skip_multi_tenancy_check: true)

    # Get platform_admin_api key
    api_key =
      from(k in ApiKey,
        where: k.role_id == ^platform_admin_api_role.id and k.tenant_id == ^platform_tenant.id,
        limit: 1
      )
      |> Repo.one!(skip_multi_tenancy_check: true)

    # Decrypt the API key to get plain value
    plain_api_key = Vault.decrypt!(api_key.key_value)

    # Get or create session for the API key
    session =
      case Repo.get_by(Session, [api_key_id: api_key.id], skip_multi_tenancy_check: true) do
        nil ->
          %Session{
            type: :api,
            api_key_id: api_key.id,
            role_id: platform_admin_api_role.id,
            tenant_id: platform_tenant.id,
            active: true,
            session_token: :crypto.strong_rand_bytes(32),
            expires_at: DateTime.add(DateTime.utc_now(), 60, :day) |> DateTime.truncate(:second),
            metadata: %{}
          }
          |> Repo.insert!(skip_multi_tenancy_check: true)

        existing_session ->
          existing_session
      end

    # Preload role for session
    session = Repo.preload(session, [:role], skip_multi_tenancy_check: true)

    # Build authenticated connection
    authenticated_conn =
      conn
      |> Plug.Conn.put_req_header("x-api-key", plain_api_key)
      |> Plug.Conn.put_req_header("content-type", "application/json")

    %{
      conn: authenticated_conn,
      platform_tenant: platform_tenant,
      platform_admin_api_role: platform_admin_api_role,
      api_key: api_key,
      plain_api_key: plain_api_key,
      session: session
    }
  end

  # TODO: Implement session-based authentication helpers when needed
  # @doc """
  # Setup helper that registers and logs in a user.
  #
  #     setup :register_and_log_in_user
  #
  # It stores an updated connection and a registered user in the
  # test context.
  # """
  # def register_and_log_in_user(%{conn: conn}) do
  #   user = AtomicFi.Factory.insert(:user)
  #   %{conn: log_in_user(conn, user), user: user}
  # end

  # @doc """
  # Logs the given `user` into the `conn`.
  #
  # It returns an updated `conn`.
  # """
  # def log_in_user(conn, user) do
  #   # Note: When implementing, use Session-based auth, not token-based
  #   conn
  #   |> Phoenix.ConnTest.init_test_session(%{})
  #   |> Plug.Conn.put_session(:session_id, session.id)
  # end
end
