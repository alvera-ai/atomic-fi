defmodule AtomicFi.UseCases.AhCountryKpResidenceTest do
  @moduledoc """
  Catalog row #15 of guides/use-cases.md — `ah_country_kp_residence`.

  Verifies the committed golden corpus at
  `corpus/zen_rules/ah_country_kp_residence/` still produces the catalog verdict
  end-to-end against the live engine. Subprocess driver — see
  `AtomicFi.UseCases.CorpusRunner`.
  """

  use ExUnit.Case, async: false

  alias AtomicFi.UseCases.CorpusRunner

  @moduletag :use_cases

  test "ah_country_kp_residence corpus matches every _expected verdict" do
    CorpusRunner.assert_golden!("ah_country_kp_residence")
  end
end
