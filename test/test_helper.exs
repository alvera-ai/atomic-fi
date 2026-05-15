ExUnit.start()

# Sweep any test_*.json rules left in priv/zenrule by crashed test runs.
AtomicFi.RulesTestHelper.cleanup_orphaned_test_rules()

# Initialise the BlocklistCache once for the seeded platform tenant so any
# test that exercises the onboarding screening path (AH/CP/BO create/refresh
# controller flows) finds a populated cache. The cache is in-memory and
# outlives the per-test sandbox transactions, so one suite-start refresh
# covers every test for the platform tenant.
#
# Runs BEFORE switching the sandbox to :manual — using the regular pool so
# no checkout/checkin dance is needed.
(fn ->
   import Ecto.Query
   alias AtomicFi.Repo
   alias AtomicFi.TenantContext.Tenant

   from(t in Tenant, where: t.tenant_type == :platform)
   |> Repo.one!(skip_multi_tenancy_check: true)
   |> then(&AtomicFi.BlocklistContext.BlocklistCache.refresh_tenant_cache(&1.id))
 end).()

Ecto.Adapters.SQL.Sandbox.mode(AtomicFi.Repo, :manual)
