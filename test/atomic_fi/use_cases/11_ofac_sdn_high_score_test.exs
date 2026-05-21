defmodule AtomicFi.UseCases.OfacSdnHighScoreTest do
  @moduledoc """
  Catalog row #11 of guides/use-cases.md — `ofac_sdn_high_score`.

  Verifies the committed golden corpus at
  `corpus/zen_rules/ofac_sdn_match/` still produces the catalog verdict
  end-to-end against the live engine. Subprocess driver — see
  `AtomicFi.UseCases.CorpusRunner`.
  """

  use ExUnit.Case, async: false

  alias AtomicFi.UseCases.CorpusRunner

  @moduletag :use_cases

  test "ofac_sdn_high_score corpus matches every _expected verdict" do
    CorpusRunner.assert_golden!("ofac_sdn_match")
  end
end
