# The default `mix test` run requires three local services up:
#   * ZenRule + Watchman — the test/atomic_fi/use_cases/* corpus tests
#     shell out to `mix corpus.validate` and hit them live.
#   * Mockoon on :8085 — every test that drives an LLM (document-parser
#     vision + Lotus AI SQL completion) is routed through it via
#     config/test.exs. Start everything with `make run-backing-services`.
ExUnit.start()

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
