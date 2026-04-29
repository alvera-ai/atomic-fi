defmodule AtomicFi.RoleContext.RoleConstants do
  @moduledoc """
  Constants for role names used throughout the application.

  Roles are organized into three categories:
  - Reserved roles: Platform-level roles that bypass RLS (root, platform_admin, platform_admin_api, system, system_api)
  - Tenant roles: Tenant-level roles without customer_id (tenant_admin, user, api)
  - Customer roles: Customer-scoped roles with customer_id (customer_admin, employee, customer_api)
  """

  # Reserved system roles (no customer_id, bypass RLS)
  # These exist in the platform tenant only
  @reserved_roles ~w(root platform_admin platform_admin_api system system_api)

  # Tenant-level roles (no customer_id)
  @tenant_admin "tenant_admin"
  @tenant_user "user"
  @tenant_api "api"

  # Customer-level roles (requires customer_id)
  @customer_admin "customer_admin"
  @employee "employee"
  @customer_api "customer_api"

  @doc """
  Returns list of reserved role names.

  These roles:
  - Bypass tenant-based RLS
  - Can only be created via database migrations
  - Cannot be created/updated through normal CRUD operations
  """
  def reserved_roles, do: @reserved_roles

  @doc """
  Checks if a role name is reserved.
  """
  def reserved?(role_name) when is_binary(role_name) do
    role_name in @reserved_roles
  end

  def reserved?(_), do: false

  # Reserved role accessors
  def root_role, do: "root"
  def platform_admin, do: "platform_admin"
  def platform_admin_api, do: "platform_admin_api"
  def system_role, do: "system"
  def system_api_role, do: "system_api"

  # Tenant role accessors
  def tenant_admin, do: @tenant_admin
  def tenant_user, do: @tenant_user
  def tenant_api, do: @tenant_api

  # Customer role accessors
  def customer_admin, do: @customer_admin
  def employee, do: @employee
  def customer_api, do: @customer_api

  @doc """
  Check if role is tenant-scoped (not customer-scoped).

  Returns true for reserved roles and tenant-level roles.
  """
  def tenant_role?(role_name) do
    role_name in [@tenant_admin, @tenant_user, @tenant_api] or reserved?(role_name)
  end

  @doc """
  Check if role is customer-scoped (requires customer_id).
  """
  def customer_role?(role_name) do
    role_name in [@customer_admin, @employee, @customer_api]
  end
end
