# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias AlveraPhoenixTemplateServer.{Config, Repo}
alias AlveraPhoenixTemplateServer.TenantContext.Tenant
alias AlveraPhoenixTemplateServer.UserContext.User
alias AlveraPhoenixTemplateServer.RoleContext.{Role, RoleConstants}
alias AlveraPhoenixTemplateServer.ApiKeyContext.ApiKey

require Logger

Logger.info("Starting database seeding...")

# Start Vault for encryption
case AlveraPhoenixTemplateServer.Vault.start_link() do
  {:ok, _} -> Logger.info("Vault started")
  {:error, {:already_started, _}} -> Logger.info("Vault already running")
end

# Read config values
tenant_name = Config.fetch!(:tenant_name)
admin_user_email = Config.fetch!(:admin_user)
admin_pass = Config.fetch!(:admin_pass)
bot_user_email = Config.fetch!(:bot_user)
root_api_key_value = Config.fetch!(:root_api_key)

Logger.info("Seeding system tenant: #{tenant_name}")

# Check if tenant already exists
existing_tenant = Repo.get_by(Tenant, [name: tenant_name], skip_multi_tenancy_check: true)

if existing_tenant do
  Logger.info("System tenant already exists, skipping seed")
  System.halt(0)
end

# Create system tenant (platform tenant)
tenant =
  Repo.insert!(
    %Tenant{
      name: tenant_name,
      tenant_type: :platform
    },
    skip_multi_tenancy_check: true
  )

Logger.info("Created system tenant: #{tenant.name} (#{tenant.id})")

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

Logger.info("Created root_role")

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

Logger.info("Created platform_admin role")

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

Logger.info("Created platform_admin_api role")

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

Logger.info("Created tenant_admin role")

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

Logger.info("Created tenant_user role")

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

Logger.info("Created tenant_api role")

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

Logger.info("Created admin user: #{admin_user_email}")

# Create bot user (no password - for automated actions)
Repo.insert!(
  %User{
    email: bot_user_email,
    hashed_password: "",
    confirmed_at: now,
    tenant_id: tenant.id
  },
  skip_multi_tenancy_check: true
)

Logger.info("Created bot user: #{bot_user_email}")

# Create root API key for programmatic access
root_api_key_hash = :crypto.hash(:sha256, root_api_key_value) |> Base.encode16(case: :lower)
encrypted_key_value = AlveraPhoenixTemplateServer.Vault.encrypt!(root_api_key_value)

%ApiKey{}
|> ApiKey.changeset(%{
  name: "Root API Key",
  key_hash: root_api_key_hash,
  key_value: encrypted_key_value,
  role_id: root_role.id,
  tenant_id: tenant.id
})
|> Repo.insert!(skip_multi_tenancy_check: true)

Logger.info("Created root API key")

# Create platform admin API key for tenant management
platform_admin_api_key_value =
  "platform_admin_#{:crypto.strong_rand_bytes(32) |> Base.encode64()}"

platform_admin_api_key_hash =
  :crypto.hash(:sha256, platform_admin_api_key_value) |> Base.encode16(case: :lower)

encrypted_platform_admin_key =
  AlveraPhoenixTemplateServer.Vault.encrypt!(platform_admin_api_key_value)

%ApiKey{}
|> ApiKey.changeset(%{
  name: "Platform Admin API Key",
  key_hash: platform_admin_api_key_hash,
  key_value: encrypted_platform_admin_key,
  role_id: platform_admin_api_role.id,
  tenant_id: tenant.id
})
|> Repo.insert!(skip_multi_tenancy_check: true)

Logger.info("Created platform admin API key")

Logger.info("""

✅ Database seeding complete!

System Tenant: #{tenant_name}
Admin User: #{admin_user_email}
Admin Password: #{admin_pass}

Root API Key: #{root_api_key_value}

You can now:
- Start the server: mix phx.server
- Access the API with: x-api-key: #{root_api_key_value}
- Test the API: curl -H "x-api-key: #{root_api_key_value}" http://localhost:4000/api/tenants
""")
