defmodule AtomicFi.CustomerContext do
  @moduledoc """
  The CustomerContext context.
  """

  import Ecto.Query, warn: false
  use AtomicFi.LoggerMacro

  alias AtomicFi.Repo
  alias AtomicFi.CustomerContext.Customer
  alias AtomicFi.RoleContext.{Role, RoleConstants, UserRoleMapping}
  alias AtomicFi.SessionContext.Session
  alias AtomicFi.UserContext.User

  @doc """
  Returns the list of customers with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.

  ## Examples

      iex> list_customers(session, %{page: 1, page_size: 20})
      {:ok, {[%Customer{}, ...], %Flop.Meta{}}}

  """
  @spec list_customers(Session.t(), map()) ::
          {:ok, {list(Customer.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_customers(session, flop_params \\ %{}), log_fields: [:flop_params] do
    Customer
    |> Flop.validate_and_run(flop_params,
      for: Customer,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single customer.

  Raises `Ecto.NoResultsError` if the Customer does not exist or user lacks access.

  ## Examples

      iex> get_customer!(session, "123")
      %Customer{}

      iex> get_customer!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_customer!(Session.t(), Ecto.UUID.t()) :: Customer.t()
  def_with_rls_and_logging get_customer!(session, id), log_fields: [:id] do
    Repo.get!(Customer, id, session: session)
  end

  @doc """
  Creates a customer with default roles.

  Automatically seeds three customer-level roles:
  - customer_admin: Full administrative access to the customer
  - employee: Default role for users in the customer
  - customer_api: Default role for API keys in the customer

  ## Examples

      iex> create_customer(session, %{field: value})
      {:ok, %Customer{}}

      iex> create_customer(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_customer(Session.t(), map()) :: {:ok, Customer.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_customer(session, attrs), log_fields: [] do
    %Customer{}
    |> Customer.changeset(attrs)
    |> Repo.insert(session: session)
    |> post_write_seed_roles()
  end

  @doc """
  Updates a customer and ensures default roles exist.

  ## Examples

      iex> update_customer(session, customer, %{field: new_value})
      {:ok, %Customer{}}

      iex> update_customer(session, customer, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_customer(Session.t(), Customer.t(), map()) ::
          {:ok, Customer.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_customer(session, %Customer{} = customer, attrs),
    log_fields: [:customer] do
    customer
    |> Customer.changeset(attrs)
    |> Repo.update(session: session)
    |> post_write_seed_roles()
  end

  @doc """
  Deletes a customer.

  ## Examples

      iex> delete_customer(session, customer)
      {:ok, %Customer{}}

      iex> delete_customer(session, customer)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_customer(Session.t(), Customer.t()) ::
          {:ok, Customer.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_customer(session, %Customer{} = customer),
    log_fields: [:customer] do
    Repo.delete(customer, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking customer changes.

  ## Examples

      iex> change_customer(customer)
      %Ecto.Changeset{data: %Customer{}}

  """
  def change_customer(%Customer{} = customer, attrs \\ %{}) do
    Customer.changeset(customer, attrs)
  end

  # Post-write hook: Seed default customer-level roles (idempotent)
  # Runs after both create and update to ensure default roles exist
  defp post_write_seed_roles({:ok, %Customer{} = customer}) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    roles = [
      %{
        name: RoleConstants.customer_admin(),
        description: "Full administrative access to the customer",
        tenant_id: customer.tenant_id,
        customer_id: customer.id,
        metadata: %{scope: "customer", permissions: ["*"]},
        inserted_at: now,
        updated_at: now
      },
      %{
        name: RoleConstants.employee(),
        description: "Default role for users in the customer",
        tenant_id: customer.tenant_id,
        customer_id: customer.id,
        metadata: %{scope: "customer", permissions: ["read", "write_own"]},
        inserted_at: now,
        updated_at: now
      },
      %{
        name: RoleConstants.customer_api(),
        description: "Default role for API keys in the customer",
        tenant_id: customer.tenant_id,
        customer_id: customer.id,
        metadata: %{scope: "customer", permissions: ["read", "write"]},
        inserted_at: now,
        updated_at: now
      }
    ]

    # Idempotent insert: on conflict do nothing
    # Use unsafe_fragment for partial unique index (has WHERE customer_id IS NOT NULL)
    Repo.insert_all(Role, roles,
      on_conflict: :nothing,
      conflict_target:
        {:unsafe_fragment, "(name, customer_id, tenant_id) WHERE customer_id IS NOT NULL"},
      skip_multi_tenancy_check: true
    )

    {:ok, customer}
  end

  defp post_write_seed_roles({:error, changeset}), do: {:error, changeset}

  # --- User Management (via Roles) ---

  @doc """
  Adds a user to a customer by assigning them a role.

  Looks up the role by name and customer_id, then creates a UserRoleMapping.
  Common role names: "employee", "customer_admin", "customer_api".

  ## Examples

      iex> add_user_to_customer(session, user_id, customer_id, "employee")
      {:ok, %User{}}

      iex> add_user_to_customer(session, user_id, customer_id, "invalid_role")
      {:error, "Role 'invalid_role' not found for customer"}

  """
  @spec add_user_to_customer(Session.t(), Ecto.UUID.t(), Ecto.UUID.t(), String.t()) ::
          {:ok, User.t()} | {:error, term()}
  def_with_rls_and_logging add_user_to_customer(session, user_id, customer_id, role_name),
    log_fields: [:user_id, :customer_id, :role_name] do
    with {:ok, role} <- get_customer_role(customer_id, role_name, session.tenant_id),
         {:ok, _mapping} <- assign_role_to_user(user_id, role.id) do
      user = Repo.get!(User, user_id, skip_multi_tenancy_check: true)
      {:ok, Repo.preload(user, :roles, skip_multi_tenancy_check: true)}
    end
  end

  @doc """
  Removes a user from a customer by removing all their customer-specific roles.

  Deletes all UserRoleMappings for roles that belong to the specified customer.

  ## Examples

      iex> remove_user_from_customer(session, user_id, customer_id)
      {2, nil}  # Deleted 2 role mappings

  """
  @spec remove_user_from_customer(Session.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {integer(), nil | [term()]}
  def_with_rls_and_logging remove_user_from_customer(_session, user_id, customer_id),
    log_fields: [:user_id, :customer_id] do
    from(ur in UserRoleMapping,
      join: r in assoc(ur, :role),
      where: ur.user_id == ^user_id,
      where: r.customer_id == ^customer_id
    )
    |> Repo.delete_all(skip_multi_tenancy_check: true)
  end

  # --- Private Helpers ---

  # Get a customer-specific role by name
  defp get_customer_role(customer_id, role_name, tenant_id) do
    role =
      from(r in Role,
        where: r.name == ^role_name,
        where: r.customer_id == ^customer_id,
        where: r.tenant_id == ^tenant_id
      )
      |> Repo.one(skip_multi_tenancy_check: true)

    case role do
      nil -> {:error, "Role '#{role_name}' not found for customer"}
      role -> {:ok, role}
    end
  end

  # Assign a role to a user (idempotent - on_conflict do nothing)
  defp assign_role_to_user(user_id, role_id) do
    %UserRoleMapping{}
    |> UserRoleMapping.changeset(%{user_id: user_id, role_id: role_id})
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:user_id, :role_id],
      skip_multi_tenancy_check: true
    )
  end
end
