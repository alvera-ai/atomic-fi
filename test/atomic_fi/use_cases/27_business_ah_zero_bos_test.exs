defmodule AtomicFi.UseCases.BusinessAhZeroBosTest do
  @moduledoc """
  Catalog row #27 of guides/use-cases.md — `business_ah_zero_bos`.

  Verifies the committed golden corpus at
  `corpus/zen_rules/business_ah_zero_bos/` still produces the catalog verdict
  end-to-end against the live engine. Subprocess driver — see
  `AtomicFi.UseCases.CorpusRunner`.
  """

  use ExUnit.Case, async: false

  alias AtomicFi.UseCases.CorpusRunner

  @moduletag :use_cases

  test "business_ah_zero_bos corpus matches every _expected verdict" do
    CorpusRunner.assert_golden!("business_ah_zero_bos")
  end
end
