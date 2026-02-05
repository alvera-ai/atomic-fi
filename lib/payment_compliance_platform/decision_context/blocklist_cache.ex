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
  """
  def init do
    :ets.new(@table_name, [:set, :named_table, :public, read_concurrency: true])
    refresh_all_caches()
    Logger.info("BlocklistCache initialized with ETS table")
  end

  @doc """
  Get exact terms MapSet for tenant+scope
  """
  def get_exact_terms(tenant_id, scope) do
    case :ets.lookup(@table_name, {tenant_id, :exact, scope}) do
      [{{^tenant_id, :exact, ^scope}, mapset}] -> mapset
      [] -> MapSet.new()
    end
  end

  @doc """
  Get combined regex pattern for tenant+scope
  """
  def get_regex_pattern(tenant_id, scope) do
    case :ets.lookup(@table_name, {tenant_id, :regex, scope}) do
      [{{^tenant_id, :regex, ^scope}, regex}] -> regex
      [] -> nil
    end
  end

  @doc """
  Get last updated timestamp for tenant (for BlocklistMatch.blocklist_updated_at)
  """
  def get_last_updated(tenant_id) do
    case :ets.lookup(@table_name, {tenant_id, :last_updated}) do
      [{{^tenant_id, :last_updated}, timestamp}] -> timestamp
      [] -> DateTime.utc_now()
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
