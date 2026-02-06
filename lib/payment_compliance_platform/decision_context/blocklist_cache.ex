defmodule PaymentCompliancePlatform.DecisionContext.BlocklistCache do
  @moduledoc """
  ETS-based blocklist cache for fast lookups.

  Refreshed automatically via Quantum scheduler (hourly).
  No GenServer - just a module with public functions.
  """
  require Logger

  import Ecto.Query
  alias PaymentCompliancePlatform.BlocklistContext.BlocklistEntry
  alias PaymentCompliancePlatform.Repo

  @table_name :blocklist_cache

  @doc """
  Initialize ETS table (called from Application.start)

  Only creates the ETS table - does NOT load data.
  Data is loaded by Quantum scheduler or explicit refresh_all_caches() calls.
  """
  def init do
    :ets.new(@table_name, [:set, :named_table, :public, read_concurrency: true])

    Logger.info(
      "BlocklistCache ETS table created (data will be loaded by scheduler or explicit refresh)"
    )
  end

  @doc """
  Check if cache is initialized for tenant (has any data loaded)

  Returns true if tenant has cache entries, false if cache is empty/uninitialized.
  """
  def cache_initialized?(tenant_id) do
    case :ets.lookup(@table_name, {tenant_id, :last_updated}) do
      [{{^tenant_id, :last_updated}, _timestamp}] -> true
      [] -> false
    end
  end

  @doc """
  Get exact terms MapSet for tenant+scope

  Returns empty MapSet if not found. Logs warning if cache is uninitialized.
  """
  def get_exact_terms(tenant_id, scope) do
    case :ets.lookup(@table_name, {tenant_id, :exact, scope}) do
      [{{^tenant_id, :exact, ^scope}, mapset}] ->
        mapset

      [] ->
        unless cache_initialized?(tenant_id) do
          Logger.warning(
            "BlocklistCache not initialized for tenant #{tenant_id} - " <>
              "returning empty set (entities will pass through). " <>
              "Cache should be populated by Quantum scheduler or manual refresh."
          )
        end

        MapSet.new()
    end
  end

  @doc """
  Get combined regex pattern for tenant+scope

  Returns nil if not found. Logs warning if cache is uninitialized.
  """
  def get_regex_pattern(tenant_id, scope) do
    case :ets.lookup(@table_name, {tenant_id, :regex, scope}) do
      [{{^tenant_id, :regex, ^scope}, regex}] ->
        regex

      [] ->
        unless cache_initialized?(tenant_id) do
          Logger.warning(
            "BlocklistCache not initialized for tenant #{tenant_id} - " <>
              "returning nil pattern (entities will pass through). " <>
              "Cache should be populated by Quantum scheduler or manual refresh."
          )
        end

        nil
    end
  end

  @doc """
  Get last updated timestamp for tenant (for BlocklistMatch.blocklist_updated_at)

  Returns current time if not found. Logs warning if cache is uninitialized.
  """
  def get_last_updated(tenant_id) do
    case :ets.lookup(@table_name, {tenant_id, :last_updated}) do
      [{{^tenant_id, :last_updated}, timestamp}] ->
        timestamp

      [] ->
        Logger.warning(
          "BlocklistCache not initialized for tenant #{tenant_id} - " <>
            "returning current timestamp. " <>
            "Cache should be populated by Quantum scheduler or manual refresh."
        )

        DateTime.utc_now()
    end
  end

  @doc """
  Health check for cache state

  Returns {:ok, stats} if cache is healthy, {:error, reason} otherwise.

  ## Examples

      iex> health_check()
      {:ok, %{table_exists: true, total_entries: 42, initialized_tenants: 3}}

      iex> health_check()
      {:error, :table_not_found}
  """
  def health_check do
    case :ets.whereis(@table_name) do
      :undefined ->
        {:error, :table_not_found}

      _table_ref ->
        all_entries = :ets.tab2list(@table_name)
        total_entries = length(all_entries)

        # Count distinct tenants with last_updated entries
        initialized_tenants =
          all_entries
          |> Enum.filter(fn
            {{_tenant_id, :last_updated}, _timestamp} -> true
            _ -> false
          end)
          |> length()

        stats = %{
          table_exists: true,
          total_entries: total_entries,
          initialized_tenants: initialized_tenants
        }

        {:ok, stats}
    end
  end

  @doc """
  Refresh cache for specific tenant
  """
  def refresh_tenant_cache(tenant_id) do
    Logger.info("Refreshing blocklist cache for tenant #{tenant_id}")

    # Load all active entries for this tenant
    entries = load_blocklist_entries(tenant_id)

    # Get max updated_at timestamp
    last_updated =
      entries
      |> Enum.map(& &1.updated_at)
      |> Enum.max(DateTime, fn -> DateTime.utc_now() end)

    :ets.insert(@table_name, {{tenant_id, :last_updated}, last_updated})

    # Process by scope
    for scope <- [:first_name, :last_name, :company_name] do
      scope_entries = Enum.filter(entries, &(&1.scope == scope))

      # Exact matches - create MapSet of downcased terms
      exact_terms =
        scope_entries
        |> Enum.filter(&(&1.entry_type == :exact && &1.active))
        |> Enum.map(&String.downcase(&1.term))
        |> MapSet.new()

      :ets.insert(@table_name, {{tenant_id, :exact, scope}, exact_terms})

      # Regex patterns - combine into single regex
      regex_patterns =
        scope_entries
        |> Enum.filter(&(&1.entry_type == :regex && &1.active))
        |> Enum.map(& &1.term)

      combined_regex =
        if Enum.empty?(regex_patterns) do
          nil
        else
          combine_regex_patterns(regex_patterns)
        end

      :ets.insert(@table_name, {{tenant_id, :regex, scope}, combined_regex})
    end

    Logger.info("Blocklist cache refreshed for tenant #{tenant_id}")
  end

  @doc """
  Refresh all tenant caches (called by Quantum scheduler)
  """
  def refresh_all_caches do
    Logger.info("Refreshing all blocklist caches")

    # Get all unique tenant IDs from blocklist_entries
    tenant_ids = get_all_tenant_ids()

    Enum.each(tenant_ids, &refresh_tenant_cache/1)

    Logger.info("All blocklist caches refreshed (#{length(tenant_ids)} tenants)")
  end

  # Private helpers

  defp load_blocklist_entries(tenant_id) do
    from(e in BlocklistEntry,
      where: e.tenant_id == ^tenant_id and e.active == true
    )
    |> Repo.all(skip_multi_tenancy_check: true)
  end

  defp get_all_tenant_ids do
    from(e in BlocklistEntry,
      where: e.active == true,
      distinct: true,
      select: e.tenant_id
    )
    |> Repo.all(skip_multi_tenancy_check: true)
  end

  defp combine_regex_patterns(patterns) do
    # Join patterns with | to create single regex
    # Example: ["^test.*", "^user\d+"] -> ~r/^test.*|^user\d+/
    combined = Enum.join(patterns, "|")

    case Regex.compile(combined) do
      {:ok, regex} ->
        regex

      {:error, reason} ->
        Logger.error("Failed to compile combined regex: #{inspect(reason)}")
        nil
    end
  end
end
