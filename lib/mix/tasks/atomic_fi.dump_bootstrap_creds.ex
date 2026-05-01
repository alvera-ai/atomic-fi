defmodule Mix.Tasks.AtomicFi.DumpBootstrapCreds do
  @shortdoc "Writes seeded tenant + admin + api key creds to a gitignored JSON file for E2E tests"

  @moduledoc """
  Reads the bootstrap credentials populated by `seed_migrations/` from the DB
  and writes them to `priv/repo/.bootstrap_creds.json` (gitignored). Used by
  `integration-tests/vitest.setup.ts` to authenticate without coupling tests
  to the encrypted DB column.

  Output shape:

      {
        "tenantSlug":           "atomic-fi-tenant",
        "adminEmail":           "admin@atomic-fi.local",
        "adminPassword":        "admin-password-dev",
        "rootApiKey":           "alvera_root_api_key_dev",
        "platformAdminApiKey":  "platform_admin_<base64>"
      }

  Usage:

      $ mix atomic_fi.dump_bootstrap_creds
      $ mix atomic_fi.dump_bootstrap_creds --output /tmp/creds.json

  Run after `mix ecto.migrate` (or `mix ecto.reset`) so the seed data exists.
  """

  use Mix.Task

  import Ecto.Query

  alias AtomicFi.{Config, Repo}
  alias AtomicFi.ApiKeyContext.ApiKey
  alias AtomicFi.TenantContext.Tenant

  @default_output "priv/repo/.bootstrap_creds.json"
  @platform_admin_api_key_name "Platform Admin API Key"

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [output: :string])
    output_path = opts[:output] || @default_output

    Mix.Task.run("app.start")

    system_tenant = Config.fetch!(:system_tenant)
    admin_user = Config.fetch!(:admin_user)
    root_api_key = Config.fetch!(:root_api_key)

    tenant_name = Keyword.fetch!(system_tenant, :name)
    tenant_slug = Keyword.fetch!(system_tenant, :slug)

    tenant =
      Repo.get_by(Tenant, [name: tenant_name], skip_multi_tenancy_check: true) ||
        Mix.raise("System tenant '#{tenant_name}' not found. Run `mix ecto.migrate` first.")

    platform_admin_api_key =
      ApiKey
      |> where([k], k.tenant_id == ^tenant.id and k.name == ^@platform_admin_api_key_name)
      |> Repo.one(skip_multi_tenancy_check: true) ||
        Mix.raise("Platform Admin API Key not found for tenant '#{tenant_name}'.")

    # The seed migration encrypts manually before insert, and EncryptedBinary
    # encrypts again on dump — so on load we get the manually-encrypted ciphertext
    # back. Decrypt once here to recover the plaintext key.
    platform_admin_api_key_value = AtomicFi.Vault.decrypt!(platform_admin_api_key.key_value)

    creds = %{
      tenantSlug: tenant_slug,
      adminEmail: Keyword.fetch!(admin_user, :email),
      adminPassword: Keyword.fetch!(admin_user, :password),
      rootApiKey: root_api_key,
      platformAdminApiKey: platform_admin_api_key_value
    }

    File.mkdir_p!(Path.dirname(output_path))
    File.write!(output_path, Jason.encode!(creds, pretty: true) <> "\n")

    Mix.shell().info("✓ Wrote bootstrap creds to #{output_path}")
  end
end
