defmodule PaymentCompliancePlatform.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use PaymentCompliancePlatform.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  import Ecto.Query

  alias PaymentCompliancePlatform.{Config, Repo}
  alias PaymentCompliancePlatform.TenantContext.Tenant
  alias PaymentCompliancePlatform.UserContext.User
  alias PaymentCompliancePlatform.RoleContext.{Role, RoleConstants}
  alias PaymentCompliancePlatform.SessionContext.Session

  using do
    quote do
      alias PaymentCompliancePlatform.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import PaymentCompliancePlatform.DataCase
      import PaymentCompliancePlatform.Factory
    end
  end

  setup tags do
    PaymentCompliancePlatform.DataCase.setup_sandbox(tags)
    {:ok, tenant: system_tenant(), session: system_session()}
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(PaymentCompliancePlatform.Repo,
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

  @doc """
  Casts request data through the AccountHolderRequest OpenAPI schema.

  This mimics what happens in the controller when OpenApiSpex validates
  and casts the request body. Generates the spec fresh for each call
  instead of caching to ensure tests use current schema definitions.

  ## Examples

      request = %{
        name: "Test Company",
        type: "business",
        interested_individuals: [
          %{first_name: "John", last_name: "Doe"}
        ],
        interested_companies: []
      }

      casted = cast_account_holder_request(request)
      assert %PaymentCompliancePlatform.OpenApiSchema.AccountHolderRequest{} = casted

  """
  def cast_account_holder_request(request_data) do
    alias PaymentCompliancePlatform.OpenApiSchema.AccountHolderRequest

    # Generate spec fresh (not cached) to reflect current schema state
    spec = OpenApiSpex.resolve_schema_modules(PaymentCompliancePlatformApi.ApiSpec.spec())
    schema = AccountHolderRequest.schema()

    case OpenApiSpex.cast_value(request_data, schema, spec) do
      {:ok, casted} ->
        casted

      {:error, errors} ->
        raise """
        Failed to cast AccountHolderRequest through OpenAPI schema.

        Errors: #{inspect(errors, pretty: true)}

        Request data: #{inspect(request_data, pretty: true)}
        """
    end
  end
end
