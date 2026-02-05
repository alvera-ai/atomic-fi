defmodule Mix.Tasks.Ecto.Migrate.Enhanced do
  @shortdoc "Runs migrations for all repos using configured migration paths"

  @moduledoc """
  Enhanced version of mix ecto.migrate that runs migrations from configured paths.

  This task is a minimal wrapper around the original ecto.migrate that:
  1. Reads migration paths from Application config (:payment_compliance_platform, :migration_paths)
  2. For each repo, calls ecto.migrate with each configured path
  3. Ensures test_migrations are run in test environment

  Usage:
      $ mix ecto.migrate.enhanced
      $ MIX_ENV=test mix ecto.migrate.enhanced

  The task respects standard ecto.migrate options and forwards them to the original task.
  """

  use Mix.Task

  require Logger

  @impl true
  def run(args) do
    # Parse repos from arguments (or use all configured repos if none specified)
    repos = Mix.Ecto.parse_repo(args)

    # Get migration paths configuration
    migration_paths_config =
      Application.get_env(:payment_compliance_platform, :migration_paths, %{})

    # Run migrations for each repo
    for repo <- repos do
      do_migrate_repo(repo, migration_paths_config, args)
    end

    Mix.shell().info("\n✓ All migrations complete!")
  end

  defp do_migrate_repo(repo, migration_paths_config, args) do
    # Get configured paths for this repo (default to ["priv/repo/migrations"])
    paths =
      Map.get(migration_paths_config, repo, ["priv/repo/migrations"])

    Logger.debug("Running migrations for #{inspect(repo)}")
    Logger.debug("  Migration paths: #{inspect(paths)}")

    # Run migrations for each path
    for path <- paths do
      do_migrate_path(repo, path, args)
    end
  end

  defp do_migrate_path(repo, path, args) do
    # Check if path exists (for debugging)
    repo_config = Application.get_env(:payment_compliance_platform, repo, [])

    app = Keyword.get(repo_config, :otp_app, :payment_compliance_platform)
    absolute_path = Application.app_dir(app, path)
    path_exists = File.exists?(absolute_path)

    Logger.debug("  Migrating from #{path} (exists: #{path_exists}, absolute: #{absolute_path})")

    # Build args for original ecto.migrate task
    # Remove any existing -r or --migrations-path args and add our own
    cleaned_args =
      Enum.reject(args, fn arg ->
        String.starts_with?(arg, "-r") or String.starts_with?(arg, "--migrations-path")
      end)

    # Call original ecto.migrate with -r and --migrations-path
    task_args = ["-r", inspect(repo), "--migrations-path", path] ++ cleaned_args

    # Clear task cache to allow running multiple times
    Mix.Task.clear()

    # Run original ecto.migrate
    Mix.Task.run("ecto.migrate", task_args)
  end
end
