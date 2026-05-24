defmodule AtomicFi.UseCases.OfacMixerUsdcTest do
  @moduledoc """
  Catalog row #34 of guides/use-cases.md — `ofac_mixer_usdc`.

  Verifies the committed golden corpus at
  `corpus/zen_rules/stableaml_wallet_blocklist/` still produces the catalog verdict
  end-to-end against the live engine. Subprocess driver — see
  `AtomicFi.UseCases.CorpusRunner`.
  """

  use ExUnit.Case, async: false

  alias AtomicFi.UseCases.CorpusRunner

  @moduletag :use_cases

  test "ofac_mixer_usdc corpus matches every _expected verdict" do
    CorpusRunner.assert_golden!("stableaml_wallet_blocklist")
  end
end
