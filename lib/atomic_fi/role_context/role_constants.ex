defmodule AtomicFi.RoleContext.RoleConstants do
  @moduledoc """
  Constants for role names used throughout the application.

  Roles are organized into two categories:
  - Reserved roles: Platform-level roles that bypass RLS (root, platform_admin, platform_admin_api, system, system_api)
  - Tenant roles: Tenant-level roles (tenant_admin, user, api)
  """

  # Reserved system roles — bypass RLS, exist in the platform tenant only,
  # created via migrations only.
  @reserved_roles ~w(root platform_admin platform_admin_api system system_api)

  # Tenant-level roles
  @tenant_admin "tenant_admin"
  @tenant_user "user"
  @tenant_api "api"

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

  @doc """
  Check if role is tenant-scoped.

  Returns true for reserved roles and tenant-level roles.
  """
  def tenant_role?(role_name) do
    role_name in [@tenant_admin, @tenant_user, @tenant_api] or reserved?(role_name)
  end
end
