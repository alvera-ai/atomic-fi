defmodule AtomicFi.Repo.Migrations.SeedSystemEntities do
  @moduledoc """
  Bootstraps the platform so it is usable after a single `mix ecto.migrate`:

    * System tenant (`tenant_type: :platform`, with slug)
    * Reserved + tenant roles
    * Admin user (with password) mapped to the root role
    * Bot user (no password)
    * Root + Platform Admin API keys

  Mirrors `platform/priv/repo/seed_migrations/*_add_admin_user.exs`.
  Idempotent: bails out if the system tenant already exists.

  Reads config:
    * `:atomic_fi, :system_tenant` — `[name: ..., slug: ...]`
    * `:atomic_fi, :admin_user`    — `[email: ..., password: ...]`
    * `:atomic_fi, :bot_user`      — `[email: ...]`
    * `:atomic_fi, :root_api_key`  — string
  """

  use Ecto.Migration

  import Ecto.Query

  alias AtomicFi.{Config, Repo}
  alias AtomicFi.TenantContext.Tenant
  alias AtomicFi.UserContext.User
  alias AtomicFi.RoleContext.{Role, RoleConstants, UserRoleMapping}
  alias AtomicFi.ApiKeyContext.ApiKey

  def up do
    system_tenant = Config.fetch!(:system_tenant)
    admin_user = Config.fetch!(:admin_user)
    bot_user = Config.fetch!(:bot_user)
    root_api_key_value = Config.fetch!(:root_api_key)

    tenant_name = Keyword.fetch!(system_tenant, :name)
    tenant_slug = Keyword.fetch!(system_tenant, :slug)
    admin_email = Keyword.fetch!(admin_user, :email)
    admin_pass = Keyword.fetch!(admin_user, :password)
    bot_email = Keyword.fetch!(bot_user, :email)

    if Repo.get_by(Tenant, [name: tenant_name], skip_multi_tenancy_check: true) do
      :ok
    else
      vault_started_by_migration =
        case AtomicFi.Vault.start_link() do
          {:ok, _pid} -> true
          {:error, {:already_started, _pid}} -> false
        end

      try do
        do_seed(tenant_name, tenant_slug, admin_email, admin_pass, bot_email, root_api_key_value)
      after
        if vault_started_by_migration, do: Supervisor.stop(AtomicFi.Vault)
      end
    end
  end

  def down do
    case Config.fetch(:system_tenant) do
      {:ok, system_tenant} ->
        tenant_name = Keyword.fetch!(system_tenant, :name)

        tenant =
          Tenant
          |> where(name: ^tenant_name)
          |> Repo.one(skip_multi_tenancy_check: true)

        if tenant, do: delete_tenant_data(tenant)

      :error ->
        :ok
    end
  end

  defp do_seed(tenant_name, tenant_slug, admin_email, admin_pass, bot_email, root_api_key_value) do
    tenant =
      Repo.insert!(
        %Tenant{
          name: tenant_name,
          slug: tenant_slug,
          tenant_type: :platform,
          enabled_regimes: AtomicFi.EnabledRegimes.default()
        },
        skip_multi_tenancy_check: true
      )

    root_role = insert_role!(tenant, RoleConstants.root_role(), "Root administrator role")

    _ = insert_role!(tenant, RoleConstants.platform_admin(), "Platform administrator with full system access")

    platform_admin_api_role =
      insert_role!(tenant, RoleConstants.platform_admin_api(), "Platform API administrator for tenant management")

    _ = insert_role!(tenant, RoleConstants.tenant_admin(), "Full administrative access to the tenant")
    _ = insert_role!(tenant, RoleConstants.tenant_user(), "Default role for human users in the tenant")
    _ = insert_role!(tenant, RoleConstants.tenant_api(), "Default role for API keys in the tenant")

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    admin =
      Repo.insert!(
        %User{
          email: admin_email,
          hashed_password: Bcrypt.hash_pwd_salt(admin_pass),
          confirmed_at: now,
          tenant_id: tenant.id
        },
        skip_multi_tenancy_check: true
      )

    Repo.insert!(
      %UserRoleMapping{user_id: admin.id, role_id: root_role.id},
      skip_multi_tenancy_check: true
    )

    Repo.insert!(
      %User{email: bot_email, hashed_password: "", confirmed_at: now, tenant_id: tenant.id},
      skip_multi_tenancy_check: true
    )

    insert_api_key!(tenant, root_role, "Root API Key", root_api_key_value)

    platform_admin_api_key_value =
      "platform_admin_#{:crypto.strong_rand_bytes(32) |> Base.encode64()}"

    insert_api_key!(tenant, platform_admin_api_role, "Platform Admin API Key", platform_admin_api_key_value)
  end

  defp insert_role!(tenant, name, description) do
    Repo.insert!(
      %Role{name: name, description: description, tenant_id: tenant.id, metadata: %{}},
      skip_multi_tenancy_check: true
    )
  end

  defp insert_api_key!(tenant, role, name, plaintext) do
    key_hash = :crypto.hash(:sha256, plaintext) |> Base.encode16(case: :lower)
    encrypted = AtomicFi.Vault.encrypt!(plaintext)

    %ApiKey{}
    |> ApiKey.changeset(%{
      name: name,
      key_hash: key_hash,
      key_value: encrypted,
      role_id: role.id,
      tenant_id: tenant.id
    })
    |> Repo.insert!(skip_multi_tenancy_check: true)
  end

  defp delete_tenant_data(tenant) do
    ApiKey
    |> where(tenant_id: ^tenant.id)
    |> Repo.delete_all(skip_multi_tenancy_check: true)

    user_ids =
      User
      |> where(tenant_id: ^tenant.id)
      |> select([u], u.id)
      |> Repo.all(skip_multi_tenancy_check: true)

    UserRoleMapping
    |> where([m], m.user_id in ^user_ids)
    |> Repo.delete_all(skip_multi_tenancy_check: true)

    User
    |> where(tenant_id: ^tenant.id)
    |> Repo.delete_all(skip_multi_tenancy_check: true)

    Role
    |> where(tenant_id: ^tenant.id)
    |> Repo.delete_all(skip_multi_tenancy_check: true)

    Repo.delete!(tenant, skip_multi_tenancy_check: true)
  end
end
