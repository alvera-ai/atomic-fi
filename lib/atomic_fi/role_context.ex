defmodule AtomicFi.RoleContext do
  @moduledoc """
  The RoleContext context.
  """

  import Ecto.Query, warn: false
  use AtomicFi.LoggerMacro

  alias AtomicFi.OpenApiSchema.RoleRequest
  alias AtomicFi.Repo
  alias AtomicFi.RoleContext.Role
  alias AtomicFi.SessionContext.Session

  # Preloads for Role responses
  @role_preloads [:tenant]

  @doc """
  Returns the list of roles with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.

  ## Examples

      iex> list_roles(session, %{page: 1, page_size: 20})
      {:ok, {[%Role{}, ...], %Flop.Meta{}}}

  """
  @spec list_roles(Session.t(), map()) ::
          {:ok, {list(Role.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_roles(%Session{} = session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    Role
    |> preload_query()
    |> Flop.validate_and_run(flop_params,
      for: Role,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single role.

  Raises `Ecto.NoResultsError` if the Role does not exist or user lacks access.

  ## Examples

      iex> get_role!(session, "123")
      %Role{}

      iex> get_role!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_role!(Session.t(), Ecto.UUID.t()) :: Role.t()
  def_with_rls_and_logging get_role!(%Session{} = session, id), log_fields: [:id] do
    Role
    |> preload_query()
    |> Repo.get!(id, session: session)
  end

  @doc """
  Creates a role.

  ## Examples

      iex> create_role(session, %{field: value})
      {:ok, %Role{}}

      iex> create_role(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_role(Session.t(), RoleRequest.t()) ::
          {:ok, Role.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_role(session, %RoleRequest{} = request), log_fields: [] do
    %Role{}
    |> Role.changeset(request)
    |> Repo.insert(session: session)
    |> preload_after_write()
  end

  @doc """
  Updates a role.

  ## Examples

      iex> update_role(session, role, %{field: new_value})
      {:ok, %Role{}}

      iex> update_role(session, role, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_role(Session.t(), Role.t(), RoleRequest.t()) ::
          {:ok, Role.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_role(session, %Role{} = role, %RoleRequest{} = request),
    log_fields: [:role] do
    role
    |> Role.changeset(request)
    |> Repo.update(session: session)
    |> preload_after_write()
  end

  @doc """
  Deletes a role.

  ## Examples

      iex> delete_role(session, role)
      {:ok, %Role{}}

      iex> delete_role(session, role)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_role(Session.t(), Role.t()) :: {:ok, Role.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_role(session, %Role{} = role), log_fields: [:role] do
    Repo.delete(role, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking role changes.

  ## Examples

      iex> change_role(role)
      %Ecto.Changeset{data: %Role{}}

  """
  def change_role(%Role{} = role, attrs \\ %{}) do
    Role.changeset(role, attrs)
  end

  # Preloads associations for role API responses.
  # Uses @role_preloads module attribute for consistent preloading.
  defp preload_query(query) do
    preload(query, ^@role_preloads)
  end

  # Preloads associations after successful write operations.
  # Uses pattern matching to handle success/error tuples without case statements.
  # Note: Uses skip_multi_tenancy_check since create/update don't receive user context.
  defp preload_after_write({:ok, %Role{} = role}) do
    {:ok, Repo.preload(role, @role_preloads, skip_multi_tenancy_check: true)}
  end

  defp preload_after_write({:error, changeset}), do: {:error, changeset}
end
