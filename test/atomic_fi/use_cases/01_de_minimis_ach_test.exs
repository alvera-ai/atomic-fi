defmodule AtomicFi.UseCases.DeMinimisAchTest do
  @moduledoc """
  Catalog row #01 of guides/use-cases.md — `de_minimis_ach`.

  Verifies the committed golden corpus at
  `corpus/zen_rules/de_minimis_ach/` still produces the catalog verdict
  end-to-end against the live engine. Subprocess driver — see
  `AtomicFi.UseCases.CorpusRunner`.
  """

  use ExUnit.Case, async: false

  alias AtomicFi.UseCases.CorpusRunner

  @moduletag :use_cases

  test "de_minimis_ach corpus matches every _expected verdict" do
    CorpusRunner.assert_golden!("de_minimis_ach")
  end
end
