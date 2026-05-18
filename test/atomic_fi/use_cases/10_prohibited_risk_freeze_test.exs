defmodule AtomicFi.UseCases.ProhibitedRiskFreezeTest do
  @moduledoc """
  Catalog row #10 of guides/use-cases.md — `prohibited_risk_freeze`.

  Verifies the committed golden corpus at
  `corpus/zen_rules/prohibited_risk_freeze/` still produces the catalog verdict
  end-to-end against the live engine. Subprocess driver — see
  `AtomicFi.UseCases.CorpusRunner`.
  """

  use ExUnit.Case, async: false

  alias AtomicFi.UseCases.CorpusRunner

  @moduletag :use_cases

  test "prohibited_risk_freeze corpus matches every _expected verdict" do
    CorpusRunner.assert_golden!("prohibited_risk_freeze")
  end
end
