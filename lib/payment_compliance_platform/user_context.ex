defmodule PaymentCompliancePlatform.UserContext do
  @moduledoc """
  The UserContext context.
  """

  import Ecto.Query, warn: false
  use PaymentCompliancePlatform.LoggerMacro

  alias PaymentCompliancePlatform.OpenApiSchema.UserRequest
  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.RoleContext.{Role, RoleConstants, UserRoleMapping}
  alias PaymentCompliancePlatform.SessionContext.Session
  alias PaymentCompliancePlatform.UserContext.User
  alias PaymentCompliancePlatform.UserContext.UserToken

  # Preloads for User responses
  @user_preloads [:roles, :tenant]

  @doc """
  Returns the list of users with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.
  Filters are passed via flop_params, e.g.:
  `%{filters: [%{field: :email, op: :ilike_and, value: "example"}]}`

  ## Examples

      iex> list_users(session, %{page: 1, page_size: 20})
      {:ok, {[%User{}, ...], %Flop.Meta{}}}

      iex> list_users(session, %{filters: [%{field: :confirmed_at, op: :empty}]})
      {:ok, {[%User{confirmed_at: nil}, ...], %Flop.Meta{}}}

  """
  @spec list_users(Session.t(), map()) ::
          {:ok, {list(User.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_users(session, flop_params \\ %{}), log_fields: [:flop_params] do
    User
    |> preload_query()
    |> Flop.validate_and_run(flop_params,
      for: User,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Returns the list of users in a customer with pagination and filtering.

  Lists users who have roles in the specified customer. Uses Flop for filtering,
  sorting, and pagination.

  ## Examples

      iex> list_customer_users(session, customer_id, %{page: 1, page_size: 20})
      {:ok, {[%User{}, ...], %Flop.Meta{}}}

  """
  @spec list_customer_users(Session.t(), Ecto.UUID.t(), map()) ::
          {:ok, {list(User.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_customer_users(session, customer_id, flop_params \\ %{}),
    log_fields: [:customer_id, :flop_params] do
    # Build base query filtered by customer through roles
    from(u in User,
      join: ur in assoc(u, :user_role_mappings),
      join: r in assoc(ur, :role),
      where: r.customer_id == ^customer_id,
      distinct: true
    )
    |> preload_query()
    |> Flop.validate_and_run(flop_params,
      for: User,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist or user lacks access.

  ## Examples

      iex> get_user!(session, "123")
      %User{}

      iex> get_user!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_user!(Session.t(), Ecto.UUID.t()) :: User.t()
  def_with_rls_and_logging get_user!(session, id), log_fields: [:id] do
    User
    |> preload_query()
    |> Repo.get!(id, session: session)
  end

  @doc """
  Creates a user and assigns the default "user" role.

  Automatically assigns the tenant-level "user" role to the new user.

  ## Examples

      iex> create_user(session, %{field: value})
      {:ok, %User{}}

      iex> create_user(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_user(Session.t(), UserRequest.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_user(session, %UserRequest{} = request), log_fields: [] do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, User.changeset(%User{}, request))
    |> Ecto.Multi.run(:role, fn _repo, _changes ->
      # Look up default "user" role for tenant
      role =
        from(r in Role,
          where: r.name == ^RoleConstants.tenant_user(),
          where: r.tenant_id == ^session.tenant_id,
          where: is_nil(r.customer_id)
        )
        |> Repo.one(skip_multi_tenancy_check: true)

      case role do
        nil -> {:error, "Default user role not found"}
        role -> {:ok, role}
      end
    end)
    |> Ecto.Multi.run(:user_role, fn _repo, %{user: user, role: role} ->
      %UserRoleMapping{}
      |> UserRoleMapping.changeset(%{user_id: user.id, role_id: role.id})
      |> Repo.insert(skip_multi_tenancy_check: true)
    end)
    |> Repo.transaction(session: session)
    |> case do
      {:ok, %{user: user}} ->
        {:ok, Repo.preload(user, @user_preloads, skip_multi_tenancy_check: true)}

      {:error, :user, changeset, _} ->
        {:error, changeset}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  @doc """
  Updates a user.

  ## Examples

      iex> update_user(session, user_record, %{field: new_value})
      {:ok, %User{}}

      iex> update_user(session, user_record, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_user(Session.t(), User.t(), UserRequest.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_user(session, %User{} = user_record, %UserRequest{} = request),
    log_fields: [:user_record] do
    user_record
    |> User.changeset(request)
    |> Repo.update(session: session)
    |> preload_after_write()
  end

  @doc """
  Deletes a user.

  ## Examples

      iex> delete_user(session, user_record)
      {:ok, %User{}}

      iex> delete_user(session, user_record)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_user(Session.t(), User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_user(session, %User{} = user_record),
    log_fields: [:user_record] do
    Repo.delete(user_record, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  # ── Authentication helpers (Bearer session API) ─────────────────────

  @doc """
  Looks up a user by email and verifies the password via Bcrypt.

  Bypasses multi-tenancy: login happens before any session exists, so there is
  no tenant context yet. Returns the user or nil. Callers must still verify the
  user's tenant membership before issuing a session.

  ## Examples

      iex> get_user_by_email_and_password("alice@example.com", "hunter2")
      %User{}

      iex> get_user_by_email_and_password("alice@example.com", "wrong")
      nil
  """
  @spec get_user_by_email_and_password(String.t(), String.t()) :: User.t() | nil
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user =
      User
      |> preload(^@user_preloads)
      |> Repo.get_by([email: email], skip_multi_tenancy_check: true)

    if User.valid_password?(user, password), do: user
  end

  @doc """
  Builds a hashed Bearer session API token for a user.

  Returns `{plaintext_token, %UserToken{}}` — the struct is unpersisted; the
  caller inserts it. Delegates to `UserToken.build_user_session_api_token/1`.
  """
  @spec build_user_session_api_token(User.t()) :: {String.t(), UserToken.t()}
  def build_user_session_api_token(%User{} = user) do
    UserToken.build_user_session_api_token(user)
  end

  @doc """
  Returns a query that verifies an incoming Bearer token and selects the
  matching `%UserToken{}` record (NOT the user). The caller uses the token
  id to look up the linked `Session` via `session.user_token_id`.
  """
  @spec verify_user_session_api_token_query(String.t()) ::
          {:ok, Ecto.Query.t()} | :error
  def verify_user_session_api_token_query(token) do
    UserToken.verify_user_session_api_token_query(token)
  end

  # Preloads associations for user API responses.
  # Uses @user_preloads module attribute for consistent preloading.
  defp preload_query(query) do
    preload(query, ^@user_preloads)
  end

  # Preloads associations after successful write operations.
  # Uses pattern matching to handle success/error tuples without case statements.
  # Note: Uses skip_multi_tenancy_check since create/update don't receive user context.
  defp preload_after_write({:ok, %User{} = user}) do
    {:ok, Repo.preload(user, @user_preloads, skip_multi_tenancy_check: true)}
  end

  defp preload_after_write({:error, changeset}), do: {:error, changeset}
end
