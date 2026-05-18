defmodule AtomicFi.UseCases.InternalBlocklistLastnameTest do
  @moduledoc """
  Catalog row #41 of guides/use-cases.md — `internal_blocklist_lastname`.

  Verifies the committed golden corpus at
  `corpus/zen_rules/internal_blocklist_lastname/` still produces the catalog verdict
  end-to-end against the live engine. Subprocess driver — see
  `AtomicFi.UseCases.CorpusRunner`.
  """

  use ExUnit.Case, async: false

  alias AtomicFi.UseCases.CorpusRunner

  @moduletag :use_cases

  test "internal_blocklist_lastname corpus matches every _expected verdict" do
    CorpusRunner.assert_golden!("internal_blocklist_lastname")
  end
end
