defmodule PaymentCompliancePlatform.SessionContext do
  @moduledoc """
  The SessionContext context.
  """

  import Ecto.Query, warn: false
  use PaymentCompliancePlatform.LoggerMacro

  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.SessionContext.Session

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
