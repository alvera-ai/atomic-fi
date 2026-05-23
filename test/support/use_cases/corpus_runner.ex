defmodule AtomicFi.UseCases.CorpusRunner do
  @moduledoc """
  Per-scenario ExUnit driver — runs `mix corpus.validate` against a
  committed golden corpus and asserts every transaction matches the
  catalog verdict pinned in the row's `_expected` block.

  Spawned as a SUBPROCESS (fresh BEAM) so the dedicated corpus schema
  is fully isolated from the test-process sandbox. The validator's
  `--reset` flag drops and re-migrates the corpus schema before each
  run, so re-running this test or running it in parallel with other
  tests has no side-effects on the test database.

  ## Why subprocess and not in-process?

  `mix corpus.validate` injects a custom Postgres `search_path` into
  the Repo and ensures a dedicated `atomic_fi_corpus` schema exists.
  Calling that mix task in-process inside an `mix test` run would
  fight with the test SQL sandbox (`Ecto.Adapters.SQL.Sandbox`) and
  Postgrex's per-process type cache. The subprocess approach matches
  exactly how an operator runs the task by hand — same code path, same
  artefacts (proof.md), same exit code semantics.
  """

  use ExUnit.CaseTemplate

  @doc """
  Run `mix corpus.validate corpus/zen_rules/<slug> --reset` and assert
  it exits 0 (all transactions match their `_expected` verdict). Prints
  the validator's stdout if the assertion fails so the per-row drift is
  visible in the test report.
  """
  @spec assert_golden!(String.t()) :: :ok
  def assert_golden!(slug) do
    corpus_path = "corpus/zen_rules/#{slug}"

    unless File.dir?(corpus_path) do
      ExUnit.Assertions.flunk("golden corpus folder missing: #{corpus_path}")
    end

    args = ["corpus.validate", corpus_path, "--reset"]

    # MIX_ENV=dev is deliberate — the screening/rule engine modules use
    # `Application.compile_env(:atomic_fi, :screening_engine, Default)`
    # which is baked at compile time. In MIX_ENV=test the Mox mock is
    # baked in, and the subprocess has no DataCase to install a
    # `stub_with`, so the first real call from corpus.validate would
    # crash with `Mox.UnexpectedCallError`. MIX_ENV=dev's compile_env
    # resolves to the live `Default` impl, which is what the validator
    # actually needs — it talks to Watchman + ZenRule end-to-end.
    {output, status} =
      System.cmd("mix", args,
        env: [{"MIX_ENV", "dev"}],
        stderr_to_stdout: true
      )

    if status != 0 do
      IO.puts(output)

      ExUnit.Assertions.flunk("""
      mix corpus.validate exited with status #{status} for slug=#{slug}

      The committed proof.md asserts every _expected verdict is met; a
      non-zero exit means at least one row diverged. See the printed
      output above for the per-row drift.

      To reproduce by hand:
        mix corpus.validate #{corpus_path} --reset
      """)
    end

    :ok
  end
end
