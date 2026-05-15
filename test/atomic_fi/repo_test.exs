defmodule AtomicFi.RepoTest do
  use AtomicFi.DataCase

  alias AtomicFi.Repo
  alias AtomicFi.SessionContext.Session
  alias AtomicFi.TenantContext.Tenant
  alias AtomicFi.UserContext.User

  defp tenant_scoped_session(tenant_id) do
    role =
      insert(:role, tenant_id: tenant_id, name: "non-admin-#{System.unique_integer([:positive])}")

    %Session{
      id: Ecto.UUID.generate(),
      type: :user,
      active: true,
      role_id: role.id,
      tenant_id: tenant_id,
      role: role,
      tenant: %Tenant{id: tenant_id}
    }
  end

  describe "prepare_query bypasses" do
    test "skip_multi_tenancy_check returns query unchanged" do
      assert [%Tenant{}] =
               Repo.all(Tenant, skip_multi_tenancy_check: true) |> List.wrap() |> Enum.take(1)
    end

    test "raises when neither session nor skip given" do
      assert_raise RuntimeError, ~r/skip_multi_tenancy_check/, fn ->
        Repo.all(User)
      end
    end

    test "delete_all skips multi-tenancy" do
      # No session, but delete_all path bypasses
      query = from(u in User, where: u.id == ^Ecto.UUID.generate())
      assert {0, nil} = Repo.delete_all(query)
    end
  end

  describe "session scope" do
    setup do
      tenant = insert(:tenant)
      session = tenant_scoped_session(tenant.id)
      {:ok, tenant: tenant, session: session}
    end

    test "applies tenant_id filter for non-admin role", %{session: session, tenant: tenant} do
      other_tenant = insert(:tenant)
      _user_visible = insert(:user, tenant_id: tenant.id)
      _user_hidden = insert(:user, tenant_id: other_tenant.id)

      users = Repo.all(User, session: session)
      assert Enum.all?(users, fn u -> u.tenant_id == tenant.id end)
      assert users != []
    end

    test "target_schemas == [] bypasses RLS", %{session: session, tenant: tenant} do
      other_tenant = insert(:tenant)
      _u1 = insert(:user, tenant_id: tenant.id)
      _u2 = insert(:user, tenant_id: other_tenant.id)

      users = Repo.all(User, session: session, target_schemas: [])
      tenants = users |> Enum.map(& &1.tenant_id) |> Enum.uniq()
      assert tenant.id in tenants and other_tenant.id in tenants
    end

    test "target_schemas with non-matching schema bypasses RLS for that query",
         %{session: session, tenant: tenant} do
      other_tenant = insert(:tenant)
      _u1 = insert(:user, tenant_id: tenant.id)
      _u2 = insert(:user, tenant_id: other_tenant.id)

      # Tell RLS to only apply to Tenant — User queries should bypass
      users = Repo.all(User, session: session, target_schemas: [Tenant])
      tenants = users |> Enum.map(& &1.tenant_id) |> Enum.uniq()
      assert tenant.id in tenants and other_tenant.id in tenants
    end

    test "platform admin session bypasses RLS" do
      admin_session = AtomicFi.DataCase.system_session()
      other_tenant = insert(:tenant)
      _u1 = insert(:user, tenant_id: other_tenant.id)

      users = Repo.all(User, session: admin_session)
      assert Enum.any?(users, fn u -> u.tenant_id == other_tenant.id end)
    end
  end

  describe "platform_admin? guards" do
    test "raises when role is not loaded" do
      session = %Session{
        id: Ecto.UUID.generate(),
        type: :user,
        active: true,
        tenant_id: Ecto.UUID.generate(),
        role: %Ecto.Association.NotLoaded{}
      }

      assert_raise RuntimeError, ~r/role must be preloaded/, fn ->
        Repo.all(User, session: session)
      end
    end

    test "raises when role is nil" do
      session = %Session{
        id: Ecto.UUID.generate(),
        type: :user,
        active: true,
        tenant_id: Ecto.UUID.generate(),
        role: nil
      }

      assert_raise RuntimeError, ~r/must have an associated role/, fn ->
        Repo.all(User, session: session)
      end
    end
  end

  describe "legacy session shape (atomize_keys)" do
    test "legacy user-like map with binary-keyed current_role" do
      tenant = insert(:tenant)
      _u = insert(:user, tenant_id: tenant.id)

      legacy = %{current_role: %{"tenant_id" => tenant.id}}
      # Path: extract_role_scope (non-Session) → atomize_keys(binary keys)
      assert is_list(Repo.all(User, session: legacy))
    end

    test "legacy user-like map with atom-keyed current_role" do
      tenant = insert(:tenant)
      _u = insert(:user, tenant_id: tenant.id)

      legacy = %{current_role: %{tenant_id: tenant.id}}
      assert is_list(Repo.all(User, session: legacy))
    end

    test "legacy user-like map with nil current_role raises (no RLS field)" do
      legacy = %{current_role: nil}

      assert_raise RuntimeError, ~r/at least one RLS field/, fn ->
        Repo.all(User, session: legacy)
      end
    end

    test "binary keys that aren't existing atoms fall back via ArgumentError rescue" do
      tenant = insert(:tenant)
      _u = insert(:user, tenant_id: tenant.id)

      # Bogus binary key that has no atom counterpart triggers String.to_existing_atom/1
      # → ArgumentError → rescue returns original (unatomized) map → has no :tenant_id
      legacy = %{current_role: %{"definitely_not_a_real_field_atom_zzzzz" => "x"}}

      assert_raise RuntimeError, ~r/at least one RLS field/, fn ->
        Repo.all(User, session: legacy)
      end
    end
  end
end
