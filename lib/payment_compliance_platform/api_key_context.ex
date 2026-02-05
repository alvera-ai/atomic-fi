defmodule PaymentCompliancePlatform.ApiKeyContext do
  @moduledoc """
  The ApiKeyContext context.
  """

  import Ecto.Query, warn: false
  use PaymentCompliancePlatform.LoggerMacro

  alias PaymentCompliancePlatform.ApiKeyContext.ApiKey
  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.SessionContext.Session

  # Preloads for ApiKey responses
  @api_key_preloads [:role, :tenant]

  @doc """
  Returns the list of api_keys with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.
  Filters are passed via flop_params, e.g.:
  `%{filters: [%{field: :name, op: :ilike_and, value: "production"}]}`

  ## Examples

      iex> list_api_keys(session, %{page: 1, page_size: 20})
      {:ok, {[%ApiKey{}, ...], %Flop.Meta{}}}

      iex> list_api_keys(session, %{filters: [%{field: :last_used_at, op: :empty}]})
      {:ok, {[%ApiKey{last_used_at: nil}, ...], %Flop.Meta{}}}

  """
  @spec list_api_keys(Session.t(), map()) ::
          {:ok, {list(ApiKey.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_api_keys(session, flop_params \\ %{}), log_fields: [:flop_params] do
    ApiKey
    |> preload_query()
    |> Flop.validate_and_run(flop_params,
      for: ApiKey,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single api_key.

  Raises `Ecto.NoResultsError` if the Api key does not exist or user lacks access.

  ## Examples

      iex> get_api_key!(session, "123")
      %ApiKey{}

      iex> get_api_key!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_api_key!(Session.t(), Ecto.UUID.t()) :: ApiKey.t()
  def_with_rls_and_logging get_api_key!(session, id), log_fields: [:id] do
    ApiKey
    |> preload_query()
    |> Repo.get!(id, session: session)
  end

  @doc """
  Creates a api_key.

  ## Examples

      iex> create_api_key(session, %{field: value})
      {:ok, %ApiKey{}}

      iex> create_api_key(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_api_key(Session.t(), map()) :: {:ok, ApiKey.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_api_key(session, attrs), log_fields: [] do
    %ApiKey{}
    |> ApiKey.changeset(attrs)
    |> Repo.insert(session: session)
    |> preload_after_write()
  end

  @doc """
  Updates a api_key.

  ## Examples

      iex> update_api_key(session, api_key, %{field: new_value})
      {:ok, %ApiKey{}}

      iex> update_api_key(session, api_key, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_api_key(Session.t(), ApiKey.t(), map()) ::
          {:ok, ApiKey.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_api_key(session, %ApiKey{} = api_key, attrs),
    log_fields: [:api_key] do
    api_key
    |> ApiKey.changeset(attrs)
    |> Repo.update(session: session)
    |> preload_after_write()
  end

  @doc """
  Deletes a api_key.

  ## Examples

      iex> delete_api_key(session, api_key)
      {:ok, %ApiKey{}}

      iex> delete_api_key(session, api_key)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_api_key(Session.t(), ApiKey.t()) ::
          {:ok, ApiKey.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_api_key(session, %ApiKey{} = api_key), log_fields: [:api_key] do
    Repo.delete(api_key, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking api_key changes.

  ## Examples

      iex> change_api_key(api_key)
      %Ecto.Changeset{data: %ApiKey{}}

  """
  def change_api_key(%ApiKey{} = api_key, attrs \\ %{}) do
    ApiKey.changeset(api_key, attrs)
  end

  @doc """
  Validates an API key by comparing the hash.

  Takes the raw API key value, hashes it, and looks up the corresponding API key.
  This function bypasses RLS since API key authentication happens before session establishment.

  ## Examples

      iex> validate_api_key("valid_api_key_123")
      {:ok, %ApiKey{}}

      iex> validate_api_key("invalid_key")
      {:error, :invalid_api_key}

  """
  @spec validate_api_key(String.t()) :: {:ok, ApiKey.t()} | {:error, :invalid_api_key}
  def validate_api_key(api_key_value) when is_binary(api_key_value) do
    # Hash the provided API key
    key_hash = :crypto.hash(:sha256, api_key_value) |> Base.encode16(case: :lower)

    # Look up the API key by hash (bypass RLS - this is pre-authentication)
    case Repo.one(
           from(k in ApiKey,
             where: k.key_hash == ^key_hash,
             preload: ^@api_key_preloads
           ),
           skip_multi_tenancy_check: true
         ) do
      nil ->
        {:error, :invalid_api_key}

      api_key ->
        # Update last_used_at timestamp (async, don't block authentication)
        Task.start(fn ->
          api_key
          |> Ecto.Changeset.change(last_used_at: DateTime.utc_now())
          |> Repo.update(skip_multi_tenancy_check: true)
        end)

        {:ok, api_key}
    end
  end

  # Preloads associations for api_key API responses.
  # Uses @api_key_preloads module attribute for consistent preloading.
  defp preload_query(query) do
    preload(query, ^@api_key_preloads)
  end

  # Preloads associations after successful write operations.
  # Uses pattern matching to handle success/error tuples without case statements.
  # Note: Uses skip_multi_tenancy_check since create/update don't receive user context.
  defp preload_after_write({:ok, %ApiKey{} = api_key}) do
    {:ok, Repo.preload(api_key, @api_key_preloads, skip_multi_tenancy_check: true)}
  end

  defp preload_after_write({:error, changeset}), do: {:error, changeset}
end
