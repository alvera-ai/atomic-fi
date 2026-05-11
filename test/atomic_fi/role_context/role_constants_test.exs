defmodule AtomicFi.RoleContext.RoleConstantsTest do
  use ExUnit.Case, async: true

  alias AtomicFi.RoleContext.RoleConstants

  describe "reserved_roles/0" do
    test "returns the canonical reserved role list" do
      assert RoleConstants.reserved_roles() == ~w(root platform_admin platform_admin_api system system_api)
    end
  end

  describe "reserved?/1" do
    for name <- ~w(root platform_admin platform_admin_api system system_api) do
      test "returns true for #{name}" do
        assert RoleConstants.reserved?(unquote(name))
      end
    end

    test "returns false for tenant-level role names" do
      refute RoleConstants.reserved?("tenant_admin")
      refute RoleConstants.reserved?("user")
      refute RoleConstants.reserved?("api")
    end

    test "returns false for unknown strings" do
      refute RoleConstants.reserved?("not_a_role")
      refute RoleConstants.reserved?("")
    end

    test "returns false for non-binary input" do
      refute RoleConstants.reserved?(nil)
      refute RoleConstants.reserved?(:root)
      refute RoleConstants.reserved?(123)
    end
  end

  describe "reserved role accessors" do
    test "return the expected literal strings" do
      assert RoleConstants.root_role() == "root"
      assert RoleConstants.platform_admin() == "platform_admin"
      assert RoleConstants.platform_admin_api() == "platform_admin_api"
      assert RoleConstants.system_role() == "system"
      assert RoleConstants.system_api_role() == "system_api"
    end
  end

  describe "tenant role accessors" do
    test "return the expected literal strings" do
      assert RoleConstants.tenant_admin() == "tenant_admin"
      assert RoleConstants.tenant_user() == "user"
      assert RoleConstants.tenant_api() == "api"
    end
  end

  describe "tenant_role?/1" do
    test "returns true for tenant-level roles" do
      assert RoleConstants.tenant_role?("tenant_admin")
      assert RoleConstants.tenant_role?("user")
      assert RoleConstants.tenant_role?("api")
    end

    test "returns true for reserved roles (they're tenant-scoped in the platform tenant)" do
      assert RoleConstants.tenant_role?("root")
      assert RoleConstants.tenant_role?("platform_admin")
      assert RoleConstants.tenant_role?("system")
    end

    test "returns false for unknown role names" do
      refute RoleConstants.tenant_role?("not_a_role")
      refute RoleConstants.tenant_role?("")
    end

    test "returns false for non-binary input" do
      refute RoleConstants.tenant_role?(nil)
      refute RoleConstants.tenant_role?(:user)
    end
  end
end
