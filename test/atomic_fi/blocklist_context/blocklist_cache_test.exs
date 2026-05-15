defmodule AtomicFi.BlocklistContext.BlocklistCacheTest do
  use AtomicFi.DataCase

  alias AtomicFi.BlocklistContext.BlocklistEntry
  alias AtomicFi.BlocklistContext.BlocklistCache

  setup %{tenant: tenant} do
    # Each test seeds its own entries; refresh after seeding.
    on_exit(fn ->
      # Clear the tenant's cache entries so tests don't leak into each other
      try do
        for scope <- [:first_name, :last_name, :company_name] do
          :ets.delete(:blocklist_cache, {tenant.id, :exact, scope})
          :ets.delete(:blocklist_cache, {tenant.id, :regex, scope})
        end

        :ets.delete(:blocklist_cache, {tenant.id, :last_updated})
      rescue
        ArgumentError -> :ok
      end
    end)

    :ok
  end

  defp insert_entry(tenant_id, scope, type, term, active \\ true) do
    Repo.insert!(
      %BlocklistEntry{
        tenant_id: tenant_id,
        scope: scope,
        entry_type: type,
        term: term,
        reason: "test",
        active: active
      },
      skip_multi_tenancy_check: true
    )
  end

  describe "cache_initialized?/1" do
    test "false before any refresh" do
      tenant_id = Ecto.UUID.generate()
      refute BlocklistCache.cache_initialized?(tenant_id)
    end

    test "true after refresh", %{tenant: tenant} do
      BlocklistCache.refresh_tenant_cache(tenant.id)
      assert BlocklistCache.cache_initialized?(tenant.id)
    end
  end

  describe "get_exact_terms/2" do
    test "returns the downcased MapSet of exact terms after refresh", %{tenant: tenant} do
      insert_entry(tenant.id, :first_name, :exact, "John")
      insert_entry(tenant.id, :first_name, :exact, "JANE")
      insert_entry(tenant.id, :first_name, :exact, "inactive", false)

      BlocklistCache.refresh_tenant_cache(tenant.id)

      terms = BlocklistCache.get_exact_terms(tenant.id, :first_name)
      assert MapSet.member?(terms, "john")
      assert MapSet.member?(terms, "jane")
      refute MapSet.member?(terms, "inactive")
    end

    test "returns empty MapSet for an uninitialized tenant" do
      assert BlocklistCache.get_exact_terms(Ecto.UUID.generate(), :first_name) == MapSet.new()
    end

    test "returns empty MapSet for a scope with no entries", %{tenant: tenant} do
      BlocklistCache.refresh_tenant_cache(tenant.id)
      assert BlocklistCache.get_exact_terms(tenant.id, :company_name) == MapSet.new()
    end
  end

  describe "get_regex_pattern/2" do
    test "returns a compiled regex combining all active patterns", %{tenant: tenant} do
      insert_entry(tenant.id, :last_name, :regex, "^smith\\d+$")
      insert_entry(tenant.id, :last_name, :regex, "doe.*")
      insert_entry(tenant.id, :last_name, :regex, "ignored.*", false)

      BlocklistCache.refresh_tenant_cache(tenant.id)

      regex = BlocklistCache.get_regex_pattern(tenant.id, :last_name)
      assert %Regex{} = regex
      assert Regex.match?(regex, "smith42")
      assert Regex.match?(regex, "doe-anything")
      refute Regex.match?(regex, "ignored")
    end

    test "returns nil when no regex entries", %{tenant: tenant} do
      BlocklistCache.refresh_tenant_cache(tenant.id)
      assert BlocklistCache.get_regex_pattern(tenant.id, :first_name) == nil
    end

    test "returns nil for an uninitialized tenant" do
      assert BlocklistCache.get_regex_pattern(Ecto.UUID.generate(), :first_name) == nil
    end
  end

  describe "get_last_updated/1" do
    test "returns the max updated_at across active entries", %{tenant: tenant} do
      insert_entry(tenant.id, :first_name, :exact, "alice")
      BlocklistCache.refresh_tenant_cache(tenant.id)

      assert %DateTime{} = BlocklistCache.get_last_updated(tenant.id)
    end

    test "returns current time for uninitialized tenant (with warning)" do
      assert %DateTime{} = BlocklistCache.get_last_updated(Ecto.UUID.generate())
    end
  end

  describe "health_check/0" do
    test "returns {:ok, stats} when the table exists" do
      assert {:ok, stats} = BlocklistCache.health_check()
      assert stats.table_exists == true
      assert is_integer(stats.total_entries)
      assert is_integer(stats.initialized_tenants)
    end
  end

  describe "refresh_all_caches/0" do
    test "refreshes every tenant that has active blocklist entries", %{tenant: tenant} do
      insert_entry(tenant.id, :first_name, :exact, "zelda")
      BlocklistCache.refresh_all_caches()
      assert BlocklistCache.cache_initialized?(tenant.id)
      assert MapSet.member?(BlocklistCache.get_exact_terms(tenant.id, :first_name), "zelda")
    end
  end

  describe "combine_regex_patterns error path" do
    test "invalid regex pattern logs error and stores nil", %{tenant: tenant} do
      # Unclosed group "(unclosed" is an invalid regex
      insert_entry(tenant.id, :first_name, :regex, "(unclosed")
      BlocklistCache.refresh_tenant_cache(tenant.id)
      assert BlocklistCache.get_regex_pattern(tenant.id, :first_name) == nil
    end
  end
end
