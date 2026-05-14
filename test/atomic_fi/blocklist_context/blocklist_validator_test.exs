defmodule AtomicFi.BlocklistContext.BlocklistValidatorTest do
  use AtomicFi.DataCase

  alias AtomicFi.BlocklistContext.BlocklistEntry
  alias AtomicFi.BlocklistContext.{BlocklistCache, BlocklistValidator}

  defp insert_entry(tenant_id, scope, type, term) do
    Repo.insert!(
      %BlocklistEntry{
        tenant_id: tenant_id,
        scope: scope,
        entry_type: type,
        term: term,
        reason: "test",
        active: true
      },
      skip_multi_tenancy_check: true
    )
  end

  describe "validate_first_name/2" do
    setup %{tenant: tenant} do
      insert_entry(tenant.id, :first_name, :exact, "blocked")
      # Normalizer capitalizes first letter, so regex must match capitalized form
      insert_entry(tenant.id, :first_name, :regex, "^Evil.*")
      BlocklistCache.refresh_tenant_cache(tenant.id)
      :ok
    end

    test "returns {:ok, normalized} for an allowed name", %{tenant: tenant} do
      assert {:ok, _} = BlocklistValidator.validate_first_name(tenant.id, "Alice")
    end

    test "returns :blocklisted on exact-term match", %{tenant: tenant} do
      assert {:error, :blocklisted, :exact, "blocked", _} =
               BlocklistValidator.validate_first_name(tenant.id, "Blocked")
    end

    test "returns :blocklisted on regex match", %{tenant: tenant} do
      assert {:error, :blocklisted, :regex, _, _} =
               BlocklistValidator.validate_first_name(tenant.id, "Evilbeast")
    end
  end

  describe "validate_last_name/2" do
    setup %{tenant: tenant} do
      insert_entry(tenant.id, :last_name, :exact, "doe")
      BlocklistCache.refresh_tenant_cache(tenant.id)
      :ok
    end

    test "returns :blocklisted on exact match", %{tenant: tenant} do
      assert {:error, :blocklisted, :exact, "doe", _} =
               BlocklistValidator.validate_last_name(tenant.id, "Doe")
    end

    test "returns {:ok, _} for an allowed last name", %{tenant: tenant} do
      assert {:ok, _} = BlocklistValidator.validate_last_name(tenant.id, "Smith")
    end
  end

  describe "validate_company_name/2" do
    setup %{tenant: tenant} do
      insert_entry(tenant.id, :company_name, :exact, "acme")
      BlocklistCache.refresh_tenant_cache(tenant.id)
      :ok
    end

    test "returns :blocklisted on exact match", %{tenant: tenant} do
      assert {:error, :blocklisted, :exact, "acme", _} =
               BlocklistValidator.validate_company_name(tenant.id, "Acme Corp LLC")
    end

    test "returns {:ok, _} for an allowed company name", %{tenant: tenant} do
      assert {:ok, _} = BlocklistValidator.validate_company_name(tenant.id, "Valid Company Inc")
    end
  end

  describe "uninitialized cache" do
    test "raises with an informative message when cache has no entry for tenant" do
      bogus_tenant = Ecto.UUID.generate()

      assert_raise RuntimeError, ~r/BlocklistCache not initialized/, fn ->
        BlocklistValidator.validate_first_name(bogus_tenant, "anyone")
      end
    end
  end
end
