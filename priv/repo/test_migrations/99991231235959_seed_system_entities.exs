defmodule PaymentCompliancePlatform.Repo.Migrations.SeedSystemEntities do
  use Ecto.Migration

  import Ecto.Query
  alias PaymentCompliancePlatform.{Config, Repo}
  alias PaymentCompliancePlatform.TenantContext.Tenant
  alias PaymentCompliancePlatform.UserContext.User
  alias PaymentCompliancePlatform.RoleContext.{Role, RoleConstants}
  alias PaymentCompliancePlatform.ApiKeyContext.ApiKey

  def up do
    # Start Vault directly for encryption (Application may not be running during migration)
    case PaymentCompliancePlatform.Vault.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Read config values using Config.fetch! (idiomatic - fails fast if missing)
    tenant_name = Config.fetch!(:tenant_name)
    admin_user_email = Config.fetch!(:admin_user)
    admin_pass = Config.fetch!(:admin_pass)
    bot_user_email = Config.fetch!(:bot_user)
    root_api_key_value = Config.fetch!(:root_api_key)

    # Create system tenant (platform tenant)
    tenant =
      Repo.insert!(
        %Tenant{
          name: tenant_name,
          tenant_type: :platform
        },
        skip_multi_tenancy_check: true
      )

    # Create root role (reserved role, bypasses RLS)
    root_role =
      Repo.insert!(
        %Role{
          name: RoleConstants.root_role(),
          description: "Root administrator role",
          tenant_id: tenant.id
        },
        skip_multi_tenancy_check: true
      )

    # Create platform_admin role (reserved role, bypasses RLS)
    _platform_admin_role =
      Repo.insert!(
        %Role{
          name: RoleConstants.platform_admin(),
          description: "Platform administrator with full system access",
          tenant_id: tenant.id,
          metadata: %{}
        },
        skip_multi_tenancy_check: true
      )

    # Create platform_admin_api role (reserved role for API access to tenant management)
    platform_admin_api_role =
      Repo.insert!(
        %Role{
          name: RoleConstants.platform_admin_api(),
          description: "Platform API administrator for tenant management",
          tenant_id: tenant.id,
          metadata: %{}
        },
        skip_multi_tenancy_check: true
      )

    # Create tenant-level roles (for normal operations in platform tenant)
    _tenant_admin_role =
      Repo.insert!(
        %Role{
          name: RoleConstants.tenant_admin(),
          description: "Full administrative access to the tenant",
          tenant_id: tenant.id,
          metadata: %{}
        },
        skip_multi_tenancy_check: true
      )

    _tenant_user_role =
      Repo.insert!(
        %Role{
          name: RoleConstants.tenant_user(),
          description: "Default role for human users in the tenant",
          tenant_id: tenant.id,
          metadata: %{}
        },
        skip_multi_tenancy_check: true
      )

    _tenant_api_role =
      Repo.insert!(
        %Role{
          name: RoleConstants.tenant_api(),
          description: "Default role for API keys in the tenant",
          tenant_id: tenant.id,
          metadata: %{}
        },
        skip_multi_tenancy_check: true
      )

    # Create admin user with password
    admin_password_hash = Bcrypt.hash_pwd_salt(admin_pass)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.insert!(
      %User{
        email: admin_user_email,
        hashed_password: admin_password_hash,
        confirmed_at: now,
        tenant_id: tenant.id
      },
      skip_multi_tenancy_check: true
    )

    # Create bot user (no password - for automated actions)
    # Use empty string for hashed_password to satisfy NOT NULL constraint
    Repo.insert!(
      %User{
        email: bot_user_email,
        hashed_password: "",
        confirmed_at: now,
        tenant_id: tenant.id
      },
      skip_multi_tenancy_check: true
    )

    # Create root API key for programmatic access
    # Store both hash (for fast validation) and encrypted value (for UI display)
    root_api_key_hash = :crypto.hash(:sha256, root_api_key_value) |> Base.encode16(case: :lower)

    # Manually encrypt the key_value using Vault (Cloak doesn't auto-encrypt in migrations)
    encrypted_key_value = PaymentCompliancePlatform.Vault.encrypt!(root_api_key_value)

    %ApiKey{}
    |> ApiKey.changeset(%{
      name: "Root API Key",
      key_hash: root_api_key_hash,
      key_value: encrypted_key_value,
      role_id: root_role.id,
      tenant_id: tenant.id
    })
    |> Repo.insert!(skip_multi_tenancy_check: true)

    # Create platform admin API key for tenant management
    platform_admin_api_key_value = "platform_admin_#{:crypto.strong_rand_bytes(32) |> Base.encode64()}"
    platform_admin_api_key_hash =
      :crypto.hash(:sha256, platform_admin_api_key_value) |> Base.encode16(case: :lower)
    encrypted_platform_admin_key = PaymentCompliancePlatform.Vault.encrypt!(platform_admin_api_key_value)

    %ApiKey{}
    |> ApiKey.changeset(%{
      name: "Platform Admin API Key",
      key_hash: platform_admin_api_key_hash,
      key_value: encrypted_platform_admin_key,
      role_id: platform_admin_api_role.id,
      tenant_id: tenant.id
    })
    |> Repo.insert!(skip_multi_tenancy_check: true)
  end

  def down do
    # Delete in reverse order (respect foreign keys)
    tenant_name = Config.fetch!(:tenant_name)

    tenant =
      Tenant
      |> where(name: ^tenant_name)
      |> Repo.one(skip_multi_tenancy_check: true)

    if tenant do
      # Delete API keys
      ApiKey
      |> where(tenant_id: ^tenant.id)
      |> Repo.delete_all(skip_multi_tenancy_check: true)

      # Delete users (cascades via foreign keys will handle sessions, etc.)
      User
      |> where(tenant_id: ^tenant.id)
      |> Repo.delete_all(skip_multi_tenancy_check: true)

      # Delete roles
      Role
      |> where(tenant_id: ^tenant.id)
      |> Repo.delete_all(skip_multi_tenancy_check: true)

      # Delete tenant
      Repo.delete!(tenant, skip_multi_tenancy_check: true)
    end
  end
end
