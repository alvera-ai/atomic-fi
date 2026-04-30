# Demo seed data for development/staging.
#
#     mix run priv/repo/seeds.exs
#
# Platform bootstrap data (system tenant, root role, admin user, root API
# keys) is created by `priv/repo/seed_migrations/` and runs as part of
# `mix ecto.migrate` — DO NOT duplicate it here.
#
# This file seeds OPTIONAL demo data for working in the system tenant:
#   * A tenant_admin demo user (email: tenant-admin@atomic-fi.local)
#   * A regular tenant_user demo user (email: user@atomic-fi.local)
#   * Demo blocklist entries (placeholder names, family relations, etc.)
#
# Idempotent: re-running is safe.

import Ecto.Query

alias AtomicFi.{Config, Repo}
alias AtomicFi.TenantContext.Tenant
alias AtomicFi.UserContext.User
alias AtomicFi.RoleContext.{Role, RoleConstants, UserRoleMapping}
alias AtomicFi.BlocklistContext.BlocklistEntry

require Logger

Logger.info("Starting demo seed (system tenant only)…")

system_tenant_cfg = Config.fetch!(:system_tenant)
tenant_name = Keyword.fetch!(system_tenant_cfg, :name)

tenant =
  case Repo.get_by(Tenant, [name: tenant_name], skip_multi_tenancy_check: true) do
    %Tenant{} = t ->
      t

    nil ->
      raise """
      System tenant #{inspect(tenant_name)} is missing. Run `mix ecto.migrate` first —
      the system tenant, roles and admin user are seeded by priv/repo/seed_migrations/.
      """
  end

# ---- Demo users ------------------------------------------------------------

now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

demo_users = [
  %{
    email: "tenant-admin@atomic-fi.local",
    role_name: RoleConstants.tenant_admin(),
    password: "demo-password"
  },
  %{
    email: "user@atomic-fi.local",
    role_name: RoleConstants.tenant_user(),
    password: "demo-password"
  }
]

inserted_user_count =
  Enum.reduce(demo_users, 0, fn %{email: email, role_name: role_name, password: password}, acc ->
    role =
      Role
      |> where(name: ^role_name)
      |> where(tenant_id: ^tenant.id)
      |> Repo.one!(skip_multi_tenancy_check: true)

    case Repo.get_by(User, [email: email], skip_multi_tenancy_check: true) do
      %User{} ->
        acc

      nil ->
        user =
          Repo.insert!(
            %User{
              email: email,
              hashed_password: Bcrypt.hash_pwd_salt(password),
              confirmed_at: now,
              tenant_id: tenant.id
            },
            skip_multi_tenancy_check: true
          )

        Repo.insert!(
          %UserRoleMapping{user_id: user.id, role_id: role.id},
          skip_multi_tenancy_check: true
        )

        acc + 1
    end
  end)

Logger.info("✓ Seeded #{inserted_user_count} demo user(s)")

# ---- Demo blocklist entries ------------------------------------------------

bot_user =
  Repo.get_by!(User, [email: Keyword.fetch!(Config.fetch!(:bot_user), :email)],
    skip_multi_tenancy_check: true
  )

entry = fn scope, type, term, reason ->
  %{
    scope: scope,
    entry_type: type,
    term: term,
    reason: reason,
    active: true,
    tenant_id: tenant.id,
    added_by_id: bot_user.id
  }
end

demo_blocklist_entries = [
  # First names — exact
  entry.(:first_name, :exact, "test", "Generic test placeholder name"),
  entry.(:first_name, :exact, "dummy", "Generic dummy placeholder name"),
  entry.(:first_name, :exact, "john", "Demo blocked first name"),
  entry.(:first_name, :exact, "dear", "Common placeholder salutation"),
  entry.(:first_name, :exact, "mom", "Family relation placeholder"),
  entry.(:first_name, :exact, "dad", "Family relation placeholder"),
  entry.(:first_name, :exact, "mother", "Family relation placeholder"),
  entry.(:first_name, :exact, "father", "Family relation placeholder"),
  entry.(:first_name, :exact, "brother", "Family relation placeholder"),
  entry.(:first_name, :exact, "sister", "Family relation placeholder"),
  entry.(:first_name, :exact, "uncle", "Family relation placeholder"),
  entry.(:first_name, :exact, "aunt", "Family relation placeholder"),
  # Last names — exact
  entry.(:last_name, :exact, "test", "Generic test surname"),
  entry.(:last_name, :exact, "doe", "Demo blocked surname"),
  # Company names — exact
  entry.(:company_name, :exact, "acme", "Generic placeholder company"),
  entry.(:company_name, :exact, "test corp", "Generic test corporation"),
  # Regex patterns
  entry.(:first_name, :regex, "^user\\d+$", "User followed by numbers (user1, user123, etc.)"),
  entry.(:first_name, :regex, "^test.*", "Names starting with 'test'"),
  entry.(:company_name, :regex, "test.*company", "Test company variations"),
  entry.(:company_name, :regex, "^(zzz|xxx|aaa)\\s", "Common placeholder prefixes")
]

inserted_blocklist_count =
  Enum.reduce(demo_blocklist_entries, 0, fn attrs, acc ->
    case Repo.insert(
           %BlocklistEntry{} |> BlocklistEntry.changeset(attrs),
           skip_multi_tenancy_check: true,
           on_conflict: :nothing,
           conflict_target: [:tenant_id, :scope, :term]
         ) do
      {:ok, _} -> acc + 1
      {:error, _} -> acc
    end
  end)

Logger.info(
  "✓ Seeded #{inserted_blocklist_count} new blocklist entries (#{length(demo_blocklist_entries)} total attempted)"
)

AtomicFi.DecisionContext.BlocklistCache.refresh_tenant_cache(tenant.id)
Logger.info("✓ Refreshed blocklist cache for tenant #{tenant.id}")

Logger.info("✅ Demo seed complete.")
