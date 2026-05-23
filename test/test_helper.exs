# `mix test` defaults: unit + integration only. Two extra-slow tag
# groups are excluded; opt in per CI workflow with `mix test --only <tag>`.
#
#   * :use_cases  — the corpus golden-regression checks under
#                   test/atomic_fi/use_cases/. Each shells out
#                   `mix corpus.validate <slug> --reset` (subprocess,
#                   MIX_ENV=dev — see corpus_runner.ex) and hits the
#                   live ZenRule + Watchman + DB end-to-end. They're
#                   regression-contract tests against the committed
#                   corpus, not unit tests of the application code, so
#                   they live in regression.yml (alongside vitest +
#                   bruno) rather than test.yml.
#
# Local backing services for the LLM-bound tests (document-parser
# vision + Lotus AI SQL completion) come from `make run-backing-services`
# (Mockoon on :8085, ZenRule on :8090, Watchman on :8084).
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
