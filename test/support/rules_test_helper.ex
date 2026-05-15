defmodule AtomicFi.RulesTestHelper do
  @moduledoc """
  Helpers for tests that write to the rules filesystem directory.

  `AtomicFi.RulesContext` reads & writes JDM files in the same
  `priv/zenrule/<rule_type>/` directory that the local ZenRule docker
  mounts. Tests share that directory with committed fixtures (e.g.
  `de_minimis.json`).

  Tests use unique filenames prefixed with `test_` so cleanup is bounded
  and committed fixtures are never touched. Mirrors the PUID + orphan-
  cleanup pattern from `Platform.MigrationTestHelper` over in the
  platform repo.

  ## Usage

      setup do
        name = RulesTestHelper.unique_rule_name()
        RulesTestHelper.register_for_cleanup(:transaction_screening, name)
        {:ok, rule_name: name}
      end

      test "writes a rule", %{session: session, rule_name: name} do
        :ok = RulesContext.write_rule(session, :transaction_screening, name, ...)
      end
  """

  alias AtomicFi.RulesContext

  @test_prefix "test_"

  @rule_types [:onboarding, :transaction_screening]

  @doc """
  Generates a unique test rule filename (prefixed for cleanup).

  Example: `"test_a1b2c3d4.json"`.
  """
  @spec unique_rule_name() :: String.t()
  def unique_rule_name do
    suffix =
      8
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)
      |> String.replace(["-", "_"], "")

    "#{@test_prefix}#{suffix}.json"
  end

  @doc """
  Registers a test rule for `on_exit` cleanup. Call from inside an ExUnit
  test or setup block.
  """
  @spec register_for_cleanup(RulesContext.rule_type(), String.t()) :: :ok
  def register_for_cleanup(rule_type, name)
      when rule_type in @rule_types and is_binary(name) do
    ExUnit.Callbacks.on_exit(fn -> drop_rule(rule_type, name) end)
    :ok
  end

  @doc """
  Deletes a test rule. No-op when absent.
  """
  @spec drop_rule(RulesContext.rule_type(), String.t()) :: :ok
  def drop_rule(rule_type, name) when rule_type in @rule_types and is_binary(name) do
    File.rm(Path.join(rule_dir(rule_type), name))
    :ok
  end

  @doc """
  Cleans up ALL orphaned `test_*.json` files in both rule_type folders.

  Run from `test/test_helper.exs` to recover from crashed test processes
  that didn't trigger their `on_exit` callbacks.
  """
  @spec cleanup_orphaned_test_rules() :: :ok
  def cleanup_orphaned_test_rules do
    for rule_type <- @rule_types do
      dir = rule_dir(rule_type)

      case File.ls(dir) do
        {:ok, names} ->
          names
          |> Enum.filter(&String.starts_with?(&1, @test_prefix))
          |> Enum.each(&File.rm(Path.join(dir, &1)))

        _ ->
          :ok
      end
    end

    :ok
  end

  defp rule_dir(rule_type) do
    Path.join([:code.priv_dir(:atomic_fi), "zenrule", RulesContext.project_name(rule_type)])
  end
end
