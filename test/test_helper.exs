# Per-scenario use-case tests (test/atomic_fi/use_cases/*) shell out to
# `mix corpus.validate corpus/zen_rules/<slug> --reset`, which spawns a
# fresh BEAM, drops + re-migrates the dedicated corpus schema, hits the
# live ZenRule + Watchman backing services, and walks the entire entity
# graph (AH → CP → BO → PA → Txn). They're slow (10s × 10 scenarios) and
# would dominate `mix test` runtime, so they're tagged :use_cases and
# excluded by default. Run them on demand with:
#
#     mix test --only use_cases
#
# (or:  mix test --include use_cases  to add them alongside the unit suite)
ExUnit.start(exclude: [:use_cases])

# Sweep any test_*.json rules left in priv/zenrule by crashed test runs.
AtomicFi.RulesTestHelper.cleanup_orphaned_test_rules()

# Initialise the BlocklistCache for every seeded tenant so any test that
# exercises the onboarding screening path (AH/CP/BO create/refresh) finds a
# populated cache. The cache is in-memory ETS — it outlives the per-test
# sandbox transactions, so one suite-start refresh covers the whole run.
#
# Runs BEFORE switching the sandbox to :manual — using the regular pool so
# no checkout/checkin dance is needed.
for tenant <- AtomicFi.Repo.all(AtomicFi.TenantContext.Tenant, skip_multi_tenancy_check: true) do
  AtomicFi.BlocklistContext.BlocklistCache.refresh_tenant_cache(tenant.id)
end

Ecto.Adapters.SQL.Sandbox.mode(AtomicFi.Repo, :manual)
