defmodule AtomicFi.UseCases.SmurfingPatternSarEligibleTest do
  @moduledoc """
  Catalog row #20 of guides/use-cases.md — `smurfing_pattern_sar_eligible`.

  Verifies the committed golden corpus at
  `corpus/zen_rules/smurfing_pattern_sar_eligible/` still produces the catalog verdict
  end-to-end against the live engine. Subprocess driver — see
  `AtomicFi.UseCases.CorpusRunner`.
  """

  use ExUnit.Case, async: false

  alias AtomicFi.UseCases.CorpusRunner

  @moduletag :use_cases

  test "smurfing_pattern_sar_eligible corpus matches every _expected verdict" do
    CorpusRunner.assert_golden!("smurfing_pattern_sar_eligible")
  end
end
