defmodule PaymentCompliancePlatform.TenantContext do
  @moduledoc """
  The TenantContext context.
  """

  import Ecto.Query, warn: false
  use PaymentCompliancePlatform.LoggerMacro

  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.RoleContext.{Role, RoleConstants}
  alias PaymentCompliancePlatform.SessionContext.Session
  alias PaymentCompliancePlatform.TenantContext.Tenant

  @doc """
  Returns the list of tenants with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.

  ## Examples

      iex> list_tenants(session, %{page: 1, page_size: 20})
      {:ok, {[%Tenant{}, ...], %Flop.Meta{}}}

  """
  @spec list_tenants(Session.t(), map()) ::
          {:ok, {list(Tenant.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_tenants(session, flop_params \\ %{}), log_fields: [:flop_params] do
    Tenant
    |> Flop.validate_and_run(flop_params,
      for: Tenant,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single tenant.

  Raises `Ecto.NoResultsError` if the Tenant does not exist or user lacks access.

  ## Examples

      iex> get_tenant!(session, "123")
      %Tenant{}

      iex> get_tenant!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_tenant!(Session.t(), Ecto.UUID.t()) :: Tenant.t()
  def_with_rls_and_logging get_tenant!(session, id), log_fields: [:id] do
    Repo.get!(Tenant, id, session: session)
  end

  @doc """
  Creates a tenant with default roles.

  Automatically seeds three tenant-level roles:
  - tenant_admin: Full administrative access to the tenant
  - user: Default role for human users in the tenant
  - api: Default role for API keys in the tenant

  ## Examples

      iex> create_tenant(session, %{field: value})
      {:ok, %Tenant{}}

      iex> create_tenant(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_tenant(Session.t(), map()) :: {:ok, Tenant.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_tenant(session, attrs), log_fields: [] do
    %Tenant{}
    |> Tenant.changeset(attrs)
    |> Repo.insert(session: session)
    |> post_write_seed_roles()
  end

  @doc """
  Updates a tenant and ensures default roles exist.

  ## Examples

      iex> update_tenant(session, tenant, %{field: new_value})
      {:ok, %Tenant{}}

      iex> update_tenant(session, tenant, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_tenant(Session.t(), Tenant.t(), map()) ::
          {:ok, Tenant.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_tenant(session, %Tenant{} = tenant, attrs),
    log_fields: [:tenant] do
    tenant
    |> Tenant.changeset(attrs)
    |> Repo.update(session: session)
    |> post_write_seed_roles()
  end

  @doc """
  Deletes a tenant.

  ## Examples

      iex> delete_tenant(session, tenant)
      {:ok, %Tenant{}}

      iex> delete_tenant(session, tenant)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_tenant(Session.t(), Tenant.t()) :: {:ok, Tenant.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_tenant(session, %Tenant{} = tenant), log_fields: [:tenant] do
    Repo.delete(tenant, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking tenant changes.

  ## Examples

      iex> change_tenant(tenant)
      %Ecto.Changeset{data: %Tenant{}}

  """
  def change_tenant(%Tenant{} = tenant, attrs \\ %{}) do
    Tenant.changeset(tenant, attrs)
  end

  # Post-write hook: Seed default tenant-level roles (idempotent)
  # Runs after both create and update to ensure default roles exist
  defp post_write_seed_roles({:ok, %Tenant{} = tenant}) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    roles = [
      %{
        name: RoleConstants.tenant_admin(),
        description: "Full administrative access to the tenant",
        tenant_id: tenant.id,
        metadata: %{scope: "tenant", permissions: ["*"]},
        inserted_at: now,
        updated_at: now
      },
      %{
        name: RoleConstants.tenant_user(),
        description: "Default role for human users in the tenant",
        tenant_id: tenant.id,
        metadata: %{scope: "tenant", permissions: ["read", "write_own"]},
        inserted_at: now,
        updated_at: now
      },
      %{
        name: RoleConstants.tenant_api(),
        description: "Default role for API keys in the tenant",
        tenant_id: tenant.id,
        metadata: %{scope: "tenant", permissions: ["read", "write"]},
        inserted_at: now,
        updated_at: now
      }
    ]

    # Idempotent insert: on conflict do nothing
    # Use unsafe_fragment for partial unique index (has WHERE customer_id IS NULL)
    Repo.insert_all(Role, roles,
      on_conflict: :nothing,
      conflict_target: {:unsafe_fragment, "(name, tenant_id) WHERE customer_id IS NULL"},
      skip_multi_tenancy_check: true
    )

    {:ok, tenant}
  end

  defp post_write_seed_roles({:error, changeset}), do: {:error, changeset}
end
