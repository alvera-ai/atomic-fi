defmodule AlveraPhoenixTemplateServer.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use AlveraPhoenixTemplateServer.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  import Ecto.Query

  alias AlveraPhoenixTemplateServer.{Config, Repo}
  alias AlveraPhoenixTemplateServer.TenantContext.Tenant
  alias AlveraPhoenixTemplateServer.UserContext.User
  alias AlveraPhoenixTemplateServer.RoleContext.{Role, RoleConstants}
  alias AlveraPhoenixTemplateServer.SessionContext.Session

  using do
    quote do
      alias AlveraPhoenixTemplateServer.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import AlveraPhoenixTemplateServer.DataCase
      import AlveraPhoenixTemplateServer.Factory
    end
  end

  setup tags do
    AlveraPhoenixTemplateServer.DataCase.setup_sandbox(tags)
    {:ok, tenant: system_tenant(), session: system_session()}
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(AlveraPhoenixTemplateServer.Repo,
        shared: not tags[:async]
      )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  Returns the system tenant seeded by migrations.
  """
  def system_tenant do
    tenant_name = Config.fetch!(:tenant_name)

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
    admin_email = Config.fetch!(:admin_user)

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
end
