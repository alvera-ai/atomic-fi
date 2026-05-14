ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(AtomicFi.Repo, :manual)

# Sweep any test_*.json rules left in priv/zenrule by crashed test runs.
AtomicFi.RulesTestHelper.cleanup_orphaned_test_rules()
