defmodule PaymentCompliancePlatform.BlocklistContext do
  @moduledoc """
  The BlocklistContext context.
  """

  import Ecto.Query, warn: false
  use PaymentCompliancePlatform.LoggerMacro

  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.BlocklistContext.BlocklistEntry
  alias PaymentCompliancePlatform.SessionContext.Session

  @doc """
  Returns the list of blocklist_entries with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.

  ## Examples

      iex> list_blocklist_entries(session, %{page: 1, page_size: 20})
      {:ok, {[%BlocklistEntry{}, ...], %Flop.Meta{}}}

  """
  @spec list_blocklist_entries(Session.t(), map()) ::
          {:ok, {list(BlocklistEntry.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_blocklist_entries(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    BlocklistEntry
    |> Flop.validate_and_run(flop_params,
      for: BlocklistEntry,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single blocklist_entry.

  Raises `Ecto.NoResultsError` if the Blocklist entry does not exist.

  ## Examples

      iex> get_blocklist_entry!(session, "123")
      %BlocklistEntry{}

      iex> get_blocklist_entry!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_blocklist_entry!(Session.t(), Ecto.UUID.t()) :: BlocklistEntry.t()
  def_with_rls_and_logging get_blocklist_entry!(session, id), log_fields: [:id] do
    Repo.get!(BlocklistEntry, id, session: session)
  end

  @doc """
  Creates a blocklist_entry.

  ## Examples

      iex> create_blocklist_entry(session, %{field: value})
      {:ok, %BlocklistEntry{}}

      iex> create_blocklist_entry(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_blocklist_entry(Session.t(), map()) ::
          {:ok, BlocklistEntry.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_blocklist_entry(session, attrs), log_fields: [:attrs] do
    %BlocklistEntry{}
    |> BlocklistEntry.changeset(attrs)
    |> Repo.insert(session: session)
  end

  @doc """
  Updates a blocklist_entry.

  ## Examples

      iex> update_blocklist_entry(session, blocklist_entry, %{field: new_value})
      {:ok, %BlocklistEntry{}}

      iex> update_blocklist_entry(session, blocklist_entry, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_blocklist_entry(Session.t(), BlocklistEntry.t(), map()) ::
          {:ok, BlocklistEntry.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_blocklist_entry(
                             session,
                             %BlocklistEntry{} = blocklist_entry,
                             attrs
                           ),
                           log_fields: [:attrs] do
    blocklist_entry
    |> BlocklistEntry.changeset(attrs)
    |> Repo.update(session: session)
  end

  @doc """
  Deletes a blocklist_entry.

  ## Examples

      iex> delete_blocklist_entry(session, blocklist_entry)
      {:ok, %BlocklistEntry{}}

      iex> delete_blocklist_entry(session, blocklist_entry)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_blocklist_entry(Session.t(), BlocklistEntry.t()) ::
          {:ok, BlocklistEntry.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_blocklist_entry(session, %BlocklistEntry{} = blocklist_entry),
    log_fields: [] do
    Repo.delete(blocklist_entry, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking blocklist_entry changes.

  ## Examples

      iex> change_blocklist_entry(blocklist_entry)
      %Ecto.Changeset{data: %BlocklistEntry{}}

  """
  def change_blocklist_entry(%BlocklistEntry{} = blocklist_entry, attrs \\ %{}) do
    BlocklistEntry.changeset(blocklist_entry, attrs)
  end
end
