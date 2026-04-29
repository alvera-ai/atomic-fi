defmodule <%= inspect context.module %> do
  @moduledoc """
  The <%= context.name %> context.
  """

  import Ecto.Query, warn: false
  use AtomicFi.LoggerMacro

  alias AtomicFi.Repo
  alias AtomicFi.SessionContext.Session
  alias <%= inspect schema.module %>

  # Preloads for <%= schema.alias %> responses
  @<%= schema.singular %>_preloads [:<%= String.trim_trailing(to_string(rls_field), "_id") %>]

  @doc """
  Returns the list of <%= schema.plural %> with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.

  ## Examples

      iex> list_<%= schema.plural %>(session, %{page: 1, page_size: 20})
      {:ok, {[%<%= inspect schema.alias %>{}, ...], %Flop.Meta{}}}

  """
  @spec list_<%= schema.plural %>(Session.t(), map()) ::
          {:ok, {list(<%= inspect schema.alias %>.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_<%= schema.plural %>(session, flop_params \\ %{}), log_fields: [:flop_params] do
    <%= inspect schema.alias %>
    |> preload_query()
    |> Flop.validate_and_run(flop_params,
      for: <%= inspect schema.alias %>,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single <%= schema.singular %>.

  Raises `Ecto.NoResultsError` if the <%= schema.human_singular %> does not exist or user lacks access.

  ## Examples

      iex> get_<%= schema.singular %>!(session, "123")
      %<%= inspect schema.alias %>{}

      iex> get_<%= schema.singular %>!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_<%= schema.singular %>!(Session.t(), Ecto.UUID.t()) :: <%= inspect schema.alias %>.t()
  def_with_rls_and_logging get_<%= schema.singular %>!(session, id), log_fields: [:id] do
    <%= inspect schema.alias %>
    |> preload_query()
    |> Repo.get!(id, session: session)
  end

  @doc """
  Creates a <%= schema.singular %>.

  ## Examples

      iex> create_<%= schema.singular %>(session, %{field: value})
      {:ok, %<%= inspect schema.alias %>{}}

      iex> create_<%= schema.singular %>(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_<%= schema.singular %>(Session.t(), map()) :: {:ok, <%= inspect schema.alias %>.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_<%= schema.singular %>(session, attrs), log_fields: [] do
    %<%= inspect schema.alias %>{}
    |> <%= inspect schema.alias %>.changeset(attrs)
    |> Repo.insert(session: session)
    |> preload_after_write()
  end

  @doc """
  Updates a <%= schema.singular %>.

  ## Examples

      iex> update_<%= schema.singular %>(session, <%= schema.singular %>, %{field: new_value})
      {:ok, %<%= inspect schema.alias %>{}}

      iex> update_<%= schema.singular %>(session, <%= schema.singular %>, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_<%= schema.singular %>(Session.t(), <%= inspect schema.alias %>.t(), map()) ::
          {:ok, <%= inspect schema.alias %>.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_<%= schema.singular %>(session, %<%= inspect schema.alias %>{} = <%= schema.singular %>, attrs),
    log_fields: [:<%= schema.singular %>] do
    <%= schema.singular %>
    |> <%= inspect schema.alias %>.changeset(attrs)
    |> Repo.update(session: session)
    |> preload_after_write()
  end

  @doc """
  Deletes a <%= schema.singular %>.

  ## Examples

      iex> delete_<%= schema.singular %>(session, <%= schema.singular %>)
      {:ok, %<%= inspect schema.alias %>{}}

      iex> delete_<%= schema.singular %>(session, <%= schema.singular %>)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_<%= schema.singular %>(Session.t(), <%= inspect schema.alias %>.t()) :: {:ok, <%= inspect schema.alias %>.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_<%= schema.singular %>(session, %<%= inspect schema.alias %>{} = <%= schema.singular %>), log_fields: [:<%= schema.singular %>] do
    Repo.delete(<%= schema.singular %>, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking <%= schema.singular %> changes.

  ## Examples

      iex> change_<%= schema.singular %>(<%= schema.singular %>)
      %Ecto.Changeset{data: %<%= inspect schema.alias %>{}}

  """
  def change_<%= schema.singular %>(%<%= inspect schema.alias %>{} = <%= schema.singular %>, attrs \\ %{}) do
    <%= inspect schema.alias %>.changeset(<%= schema.singular %>, attrs)
  end

  # Preloads associations for <%= schema.singular %> API responses.
  # Uses @<%= schema.singular %>_preloads module attribute for consistent preloading.
  defp preload_query(query) do
    preload(query, ^@<%= schema.singular %>_preloads)
  end

  # Preloads associations after successful write operations.
  # Uses pattern matching to handle success/error tuples without case statements.
  # Note: Uses skip_multi_tenancy_check since create/update don't receive user context.
  defp preload_after_write({:ok, %<%= inspect schema.alias %>{} = <%= schema.singular %>}) do
    {:ok, Repo.preload(<%= schema.singular %>, @<%= schema.singular %>_preloads, skip_multi_tenancy_check: true)}
  end

  defp preload_after_write({:error, changeset}), do: {:error, changeset}
end
