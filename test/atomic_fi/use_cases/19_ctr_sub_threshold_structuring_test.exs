defmodule AtomicFi.UseCases.CtrSubThresholdStructuringTest do
  @moduledoc """
  Catalog row #19 of guides/use-cases.md — `ctr_sub_threshold_structuring`.

  Verifies the committed golden corpus at
  `corpus/zen_rules/ctr_structuring/` still produces the catalog verdict
  end-to-end against the live engine. Subprocess driver — see
  `AtomicFi.UseCases.CorpusRunner`.
  """

  use ExUnit.Case, async: false

  alias AtomicFi.UseCases.CorpusRunner

  @moduletag :use_cases

  test "ctr_sub_threshold_structuring corpus matches every _expected verdict" do
    CorpusRunner.assert_golden!("ctr_structuring")
  end
end
