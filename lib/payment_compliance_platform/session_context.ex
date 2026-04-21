defmodule PaymentCompliancePlatform.SessionContext do
  @moduledoc """
  The SessionContext context.
  """

  import Ecto.Query, warn: false
  use PaymentCompliancePlatform.LoggerMacro

  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.SessionContext.Session
  alias PaymentCompliancePlatform.SessionContext.SessionManager
  alias PaymentCompliancePlatform.TenantContext.Tenant
  alias PaymentCompliancePlatform.UserContext
  alias PaymentCompliancePlatform.UserContext.User

  # Preloads for Session responses
  @session_preloads [:user, :api_key, :role, :tenant]

  @doc """
  Returns the list of sessions with pagination and filtering.

  ## Examples

      iex> list_sessions(session, %Flop{})
      {:ok, {[%Session{}], %Flop.Meta{}}}

  """
  @spec list_sessions(Session.t(), map()) ::
          {:ok, {list(Session.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_sessions(session, flop \\ %Flop{}), log_fields: [:flop] do
    Session
    |> preload_query()
    |> Flop.validate_and_run(flop, for: Session, query_opts: [session: session])
  end

  @doc """
  Gets a single session.

  Raises `Ecto.NoResultsError` if the Session does not exist.

  ## Examples

      iex> get_session!(session, 123)
      %Session{}

      iex> get_session!(session, 456)
      ** (Ecto.NoResultsError)

  """
  @spec get_session!(Session.t(), Ecto.UUID.t()) :: Session.t()
  def_with_rls_and_logging get_session!(session, id), log_fields: [:id] do
    Session
    |> preload_query()
    |> Repo.get!(id, session: session)
  end

  @doc """
  Creates a session.

  Note: Does not require authentication session (used during login).

  ## Examples

      iex> create_session(%{field: value})
      {:ok, %Session{}}

      iex> create_session(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_session(attrs) do
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert(skip_multi_tenancy_check: true)
    |> preload_after_write()
  end

  @doc """
  Updates a session.

  ## Examples

      iex> update_session(session, %{field: new_value})
      {:ok, %Session{}}

      iex> update_session(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_session(%Session{} = session, attrs) do
    session
    |> Session.changeset(attrs)
    |> Repo.update(skip_multi_tenancy_check: true)
    |> preload_after_write()
  end

  @doc """
  Deletes a session.

  ## Examples

      iex> delete_session(session)
      {:ok, %Session{}}

      iex> delete_session(session)
      {:error, %Ecto.Changeset{}}

  """
  def delete_session(%Session{} = session) do
    Repo.delete(session, skip_multi_tenancy_check: true)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking session changes.

  ## Examples

      iex> change_session(session)
      %Ecto.Changeset{data: %Session{}}

  """
  def change_session(%Session{} = session, attrs \\ %{}) do
    Session.changeset(session, attrs)
  end

  @doc """
  Exchanges credentials for a Bearer session.

  Given a `SessionRequest` (email + password + tenant_slug + optional
  expires_in) and request metadata, authenticates the user, verifies tenant
  membership, resolves a role, and creates a Bearer Session via
  `SessionManager.create_user_session_api_token/4`.

  Returns `{:ok, %Session{bearer: plaintext_token}}` on success — the session
  is preloaded with user/role/tenant and the virtual `:bearer` field carries
  the plaintext token (returned once).

  Returns `{:error, :unauthorized}` for any authentication / tenant-access
  / role-assignment failure — avoids leaking which check failed to callers.
  """
  @spec sign_in(map(), map()) :: {:ok, Session.t()} | {:error, :unauthorized}
  def sign_in(%{} = request, metadata \\ %{}) do
    with {:ok, user} <- authenticate_user(request),
         {:ok, tenant} <- fetch_tenant_by_slug(Map.get(request, :tenant_slug)),
         :ok <- verify_user_belongs_to_tenant(user, tenant),
         {:ok, role} <- pick_primary_role(user) do
      {plaintext_token, session} =
        SessionManager.create_user_session_api_token(user, tenant, role,
          expires_in: Map.get(request, :expires_in),
          metadata: metadata
        )

      {:ok, %{session | bearer: plaintext_token}}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp authenticate_user(%{} = request) do
    case UserContext.get_user_by_email_and_password(
           Map.get(request, :email),
           Map.get(request, :password)
         ) do
      %User{} = user -> {:ok, user}
      nil -> :error
    end
  end

  defp fetch_tenant_by_slug(slug) when is_binary(slug) do
    case Repo.get_by(Tenant, [slug: slug], skip_multi_tenancy_check: true) do
      %Tenant{} = tenant -> {:ok, tenant}
      nil -> :error
    end
  end

  defp fetch_tenant_by_slug(_), do: :error

  defp verify_user_belongs_to_tenant(%User{tenant_id: tid}, %Tenant{id: tid}), do: :ok
  defp verify_user_belongs_to_tenant(_, _), do: :error

  # Users have a many-to-many to Roles via UserRoleMapping; membership is
  # implicit via User.tenant_id. Pick the lowest-id role for determinism.
  defp pick_primary_role(%User{roles: roles}) when is_list(roles) and roles != [] do
    {:ok, Enum.min_by(roles, & &1.id)}
  end

  defp pick_primary_role(_), do: :error

  # Preloads associations for session API responses.
  # Uses @session_preloads module attribute for consistent preloading.
  defp preload_query(query) do
    preload(query, ^@session_preloads)
  end

  # Preloads associations after successful write operations.
  # Uses pattern matching to handle success/error tuples without case statements.
  # Note: Uses skip_multi_tenancy_check since create/update/delete operate on the session being modified.
  defp preload_after_write({:ok, %Session{} = session}) do
    {:ok, Repo.preload(session, @session_preloads, skip_multi_tenancy_check: true)}
  end

  defp preload_after_write({:error, changeset}), do: {:error, changeset}
end
