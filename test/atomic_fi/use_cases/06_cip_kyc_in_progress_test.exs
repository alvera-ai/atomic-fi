defmodule AtomicFi.UseCases.CipKycInProgressTest do
  @moduledoc """
  Catalog row #06 of guides/use-cases.md — `cip_kyc_in_progress`.

  Verifies the committed golden corpus at
  `corpus/zen_rules/cip_kyc_gate/` still produces the catalog verdict
  end-to-end against the live engine. Subprocess driver — see
  `AtomicFi.UseCases.CorpusRunner`.
  """

  use ExUnit.Case, async: false

  alias AtomicFi.UseCases.CorpusRunner

  @moduletag :use_cases

  test "cip_kyc_in_progress corpus matches every _expected verdict" do
    CorpusRunner.assert_golden!("cip_kyc_gate")
  end
end
