defmodule AtomicFi.TenantContextTest do
  use AtomicFi.DataCase

  alias AtomicFi.TenantContext

  describe "tenants" do
    alias AtomicFi.TenantContext.Tenant

    import AtomicFi.Factory

    @invalid_attrs %{name: nil, status: nil, metadata: nil, slug: nil}

    test "list_tenants/2 returns all tenants", %{session: session} do
      {:ok, {tenants, _meta}} = TenantContext.list_tenants(session)
      assert length(tenants) == 1
      assert Enum.any?(tenants, fn t -> t.id == session.tenant_id end)
    end

    test "get_tenant!/2 returns the tenant with given id", %{session: session} do
      assert TenantContext.get_tenant!(session, session.tenant_id).id == session.tenant_id
    end

    test "create_tenant/2 with valid data creates a tenant", %{session: session} do
      valid_attrs = %{
        name: "some name",
        status: :active,
        tenant_type: :standard,
        metadata: %{},
        slug: "some-slug"
      }

      assert {:ok, %Tenant{} = tenant} = TenantContext.create_tenant(session, valid_attrs)
      assert tenant.name == "some name"
      assert tenant.status == :active
      assert tenant.tenant_type == :standard
      assert tenant.metadata == %{}
      assert tenant.slug == "some-slug"
    end

    test "create_tenant/2 with invalid data returns error changeset", %{session: session} do
      assert {:error, %Ecto.Changeset{}} = TenantContext.create_tenant(session, @invalid_attrs)
    end

    test "update_tenant/3 with valid data updates the tenant", %{session: session} do
      tenant = session.tenant

      update_attrs = %{
        name: "some updated name",
        status: :inactive,
        metadata: %{},
        slug: "some-updated-slug"
      }

      assert {:ok, %Tenant{} = tenant} =
               TenantContext.update_tenant(session, tenant, update_attrs)

      assert tenant.name == "some updated name"
      assert tenant.status == :inactive
      assert tenant.metadata == %{}
      assert tenant.slug == "some-updated-slug"
    end

    test "update_tenant/3 with invalid data returns error changeset", %{session: session} do
      tenant = session.tenant

      assert {:error, %Ecto.Changeset{}} =
               TenantContext.update_tenant(session, tenant, @invalid_attrs)

      assert TenantContext.get_tenant!(session, tenant.id).id == tenant.id
    end

    test "delete_tenant/2 deletes the tenant", %{session: session} do
      tenant = insert(:tenant)

      assert {:ok, %Tenant{}} = TenantContext.delete_tenant(session, tenant)
      assert_raise Ecto.NoResultsError, fn -> TenantContext.get_tenant!(session, tenant.id) end
    end

    test "change_tenant/1 returns a tenant changeset" do
      tenant = insert(:tenant)
      assert %Ecto.Changeset{} = TenantContext.change_tenant(tenant)
    end
  end
end
