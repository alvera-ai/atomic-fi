defmodule AtomicFi.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use AtomicFi.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  import Ecto.Query

  alias AtomicFi.{Config, Repo}
  alias AtomicFi.TenantContext.Tenant
  alias AtomicFi.UserContext.User
  alias AtomicFi.RoleContext.{Role, RoleConstants}
  alias AtomicFi.SessionContext.Session

  using do
    quote do
      alias AtomicFi.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import AtomicFi.DataCase
      import AtomicFi.Factory
    end
  end

  setup tags do
    AtomicFi.DataCase.setup_sandbox(tags)
    AtomicFi.DataCase.setup_screening_engine_mock(tags)
    AtomicFi.DataCase.setup_rule_engine_mock(tags)
    tenant = system_tenant()
    # Re-init BlocklistCache for the system tenant on every test — cheap (single
    # ETS insert + a Repo.all of usually-empty blocklist entries) and immune to
    # test-order pollution from other tests that overwrite ETS state.
    AtomicFi.BlocklistContext.BlocklistCache.refresh_tenant_cache(tenant.id)
    {:ok, tenant: tenant, session: system_session()}
  end

  @doc """
  Default: AtomicFi.ScreeningEngineMock delegates to the real engine
  (which hits the local moov/watchman container). Individual tests opt-in to
  canned results via `Mox.expect(AtomicFi.ScreeningEngineMock, :screen_account_holder,
  fn _, _, _ -> ... end)`.
  """
  def setup_screening_engine_mock(tags) do
    Mox.set_mox_from_context(tags)
    Mox.stub_with(AtomicFi.ScreeningEngineMock, AtomicFi.ScreeningEngine.Default)
    Mox.verify_on_exit!()
    :ok
  end

  @doc """
  Default: AtomicFi.RuleEngineMock delegates to the real engine (which hits
  the local GoRules Agent container). Individual tests opt-in to canned
  per-rule controls via
  `Mox.expect(AtomicFi.RuleEngineMock, :evaluate_rule, fn _, _, _, _ -> ... end)`.
  """
  def setup_rule_engine_mock(tags) do
    Mox.set_mox_from_context(tags)
    Mox.stub_with(AtomicFi.RuleEngineMock, AtomicFi.RuleEngine.Default)
    Mox.verify_on_exit!()
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(AtomicFi.Repo,
        shared: not tags[:async]
      )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  Returns the system tenant seeded by migrations.
  """
  def system_tenant do
    tenant_name = Config.fetch!([:system_tenant, :name])

    Tenant
    |> where(name: ^tenant_name)
    |> Repo.one!(skip_multi_tenancy_check: true)
  end

  @doc """
  Returns an in-memory system session for the admin user with root role.
  Used for tests to bypass RLS or test as admin.
  """
  def system_session do
    tenant = system_tenant()
    admin_email = Config.fetch!([:admin_user, :email])

    # Get admin user
    user =
      User
      |> where(email: ^admin_email)
      |> where(tenant_id: ^tenant.id)
      |> Repo.one!(skip_multi_tenancy_check: true)

    # Get root role
    role =
      Role
      |> where(name: ^RoleConstants.root_role())
      |> where(tenant_id: ^tenant.id)
      |> Repo.one!(skip_multi_tenancy_check: true)

    # Create in-memory session struct with preloaded associations
    %Session{
      id: Ecto.UUID.generate(),
      type: :user,
      active: true,
      user_id: user.id,
      role_id: role.id,
      tenant_id: tenant.id,
      session_token: :crypto.strong_rand_bytes(32),
      expires_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:microsecond),
      user: user,
      role: role,
      tenant: tenant
    }
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc """
  Initialize blocklist cache for a tenant.

  Call this helper before tests that perform screening operations
  to ensure the cache is initialized and prevent uninitialized cache exceptions.

  ## Examples

      test "screens account holder", %{session: session} do
        init_blocklist_cache(session.tenant_id)

        request = %{name: "Test", type: "individual", ...}
        assert {:ok, decision} = ScreeningEngine.screen_account_holder(session, request)
      end

  """
  def init_blocklist_cache(tenant_id) do
    AtomicFi.BlocklistContext.BlocklistCache.refresh_tenant_cache(tenant_id)
  end

  @doc """
  Seed demo blocklist entries for a tenant and initialize cache.

  Creates the same blocklist entries as seeds.exs for testing purposes.
  """
  def seed_blocklist_for_tenant(tenant_id) do
    alias AtomicFi.BlocklistContext.BlocklistEntry

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
      %{
        scope: :first_name,
        entry_type: :exact,
        term: "dummy",
        reason: "Demo blocked",
        active: true
      },
      %{
        scope: :first_name,
        entry_type: :exact,
        term: "dear",
        reason: "Demo blocked",
        active: true
      },
      %{
        scope: :first_name,
        entry_type: :exact,
        term: "mom",
        reason: "Demo blocked",
        active: true
      },
      # Exact matches - Last names
      %{scope: :last_name, entry_type: :exact, term: "doe", reason: "Demo blocked", active: true},
      %{
        scope: :last_name,
        entry_type: :exact,
        term: "test",
        reason: "Demo blocked",
        active: true
      },
      # Exact matches - Company names
      %{
        scope: :company_name,
        entry_type: :exact,
        term: "acme",
        reason: "Demo blocked",
        active: true
      },
      %{
        scope: :company_name,
        entry_type: :exact,
        term: "test corp",
        reason: "Demo blocked",
        active: true
      },
      # Regex patterns - First names (case-insensitive for normalized names)
      %{
        scope: :first_name,
        entry_type: :regex,
        term: "(?i)^user\\d+$",
        reason: "User + number pattern",
        active: true
      },
      %{
        scope: :first_name,
        entry_type: :regex,
        term: "(?i)^test.*",
        reason: "Test prefix",
        active: true
      },
      # Regex patterns - Company names (already uppercase normalized)
      %{
        scope: :company_name,
        entry_type: :regex,
        term: "TEST.*COMPANY",
        reason: "Test company",
        active: true
      },
      %{
        scope: :company_name,
        entry_type: :regex,
        term: "^(ZZZ|XXX|AAA)\\s",
        reason: "Placeholder prefix",
        active: true
      }
    ]

    Enum.each(demo_entries, fn entry_attrs ->
      %BlocklistEntry{}
      |> BlocklistEntry.changeset(Map.put(entry_attrs, :tenant_id, tenant_id))
      |> Repo.insert!(skip_multi_tenancy_check: true)
    end)

    # Refresh cache after seeding
    AtomicFi.BlocklistContext.BlocklistCache.refresh_tenant_cache(tenant_id)
  end
end
