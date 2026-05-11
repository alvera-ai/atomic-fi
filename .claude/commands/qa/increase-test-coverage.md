---
name: increase-test-coverage
description: Iteratively lift a specific atomic-fi module's test coverage toward 100% by targeting its test files with coveralls
when_to_use:
  - Boosting coverage on a newly implemented context, controller, or worker before PR
  - Closing gaps after a refactor changed branches without updating tests
  - Pre-merge coverage audit of a high-risk context (compliance_screening, account_holder, legal_entity, transactions)
related_commands:
  - /qa:fix-failing-tests (if a new test fails — diagnose before continuing)
  - /qa:check-api-quality (controllers only — structural drift checker)
  - /qa:quality-checks (run before committing — REQUIRED)
---

# Increase Code Coverage to 100%

Iteratively lift a specific module's coverage toward 100%. Runs a
**module-scoped** coveralls subset (not the full suite) — sidesteps slow
heavy tests by design, so no tiered-test gymnastics needed.

## Usage

```
/qa:increase-test-coverage <module_path>
```

**Examples:**
```
/qa:increase-test-coverage lib/atomic_fi/account_holder_context.ex
/qa:increase-test-coverage lib/atomic_fi/compliance_screening_context.ex
/qa:increase-test-coverage lib/atomic_fi_api/controllers/account_holder_controller.ex
```

## Instructions

Follow these steps to systematically increase coverage to 100%.

---

### Step 1: Verify Module Not Excluded

Check `coveralls.json` to ensure the target module is NOT in `skip_files`:

```bash
cat coveralls.json | grep -i "$(basename <module_path> .ex)"
```

If found in `skip_files`, the module is intentionally untracked (generated
scaffold like `core_components.ex`, dev tooling like `lib/mix/tasks/`,
factory files like `test/support/factory/`). If you genuinely want coverage
on it, remove it from `skip_files` before proceeding. Otherwise pick a
different target.

---

### Step 2: Curate Test File List in Moduledoc

Check if the target module already has a `## Test Coverage` section in its
`@moduledoc`. If it does, use those globs directly and skip to Step 3.

If not, **curate** the list — don't blindly grep. A context module referenced by
50 test files doesn't need all 50; most are downstream consumers that don't
exercise the target's code paths. Apply judgment:

**Step 2a: Identify direct test files**

These test the module's public API directly (context functions, schema
changesets, worker `perform/1`):

    test/atomic_fi/<context_name>_test.exs
    test/atomic_fi/<context_name>/*_test.exs

For a context like `lib/atomic_fi/account_holder_context.ex`:

    test/atomic_fi/account_holder_context_test.exs
    test/atomic_fi/account_holder_context/*_test.exs

**Step 2b: Identify integration/lifecycle tests (1 degree deeper)**

End-to-end flows that drive the module through realistic paths
(e.g. compliance-screening lifecycle tests exercise account-holder + legal-entity
+ counterparty traversal under real Watchman). Include them — they cover deep
pipeline paths that unit tests miss.

    test/atomic_fi/compliance_screening_context/*_test.exs

**Step 2c: Identify HTTP/controller tests**

If the module is called by a controller, include the controller's test file:

    test/atomic_fi_api/controllers/<resource>_controller_test.exs

**Step 2d: Identify use-case scenario tests (atomic-fi specific)**

For Block 1 work, scenarios under `test/atomic_fi/use_cases/` exercise the
catalog in [`guides/use-cases.md`](../../../guides/use-cases.md). If the
module is hit by any scenario:

    test/atomic_fi/use_cases/<NN>_<slug>_test.exs

**Step 2e: Write the curated list into the module's `@moduledoc`**

Add a `## Test Coverage` section at the end of the `@moduledoc` with the
curated globs. This persists the judgment call for future coverage runs:

```elixir
@moduledoc """
...existing docs...

## Test Coverage

    Direct (unit + context tests):
        test/atomic_fi/account_holder_context_test.exs
        test/atomic_fi/account_holder_context/*_test.exs

    Integration (lifecycle + flow tests):
        test/atomic_fi/compliance_screening_context/account_holder_screening_test.exs

    HTTP (controller tests):
        test/atomic_fi_api/controllers/account_holder_controller_test.exs

    Use-case scenarios:
        test/atomic_fi/use_cases/01_ofac_sdn_exact_match_test.exs
"""
```

**Judgment rules:**

- Include test files that call the module's public functions directly
- Include lifecycle/integration tests that drive the module's code through
  realistic end-to-end flows (compliance pipeline, beneficial-owner traversal,
  RLS scoping)
- Exclude downstream consumer tests that only reference the module's structs
  via factories (e.g. a transaction test that imports `AccountHolderFactory`
  but doesn't call `AccountHolderContext` functions)
- Use globs (`*_test.exs`) to keep the list maintainable

---

### Step 3: Generate Targeted Coverage Report

Expand the globs from the moduledoc's `## Test Coverage` section and run
coveralls. Back up the JSON so partial re-runs don't overwrite the baseline:

```bash
# Generate JSON coverage with curated test files
MIX_ENV=test mix coveralls.json -- <expanded_glob_1> <expanded_glob_2> ... 2>&1 | tee /tmp/coverage.txt

# Back up the baseline
cp cover/excoveralls.json /tmp/<module>-excoveralls-backup.json
```

This creates `cover/excoveralls.json` with detailed line-by-line coverage.

---

### Step 4: Get Coverage Stats with Python

Use Python to parse coverage (more reliable than jq with shell escaping):

```bash
python3 -c "
import json
with open('cover/excoveralls.json') as f:
    data = json.load(f)
for sf in data['source_files']:
    if '<module>.ex' in sf['name'] and '<module>/' not in sf['name']:
        cov = sf['coverage']
        uncovered = [i+1 for i, c in enumerate(cov) if c == 0]
        total = len([c for c in cov if c is not None])
        covered = len([c for c in cov if c and c > 0])
        print(f\"{sf['name']}: {covered}/{total} = {100*covered/total:.1f}%\")
        print(f'Uncovered lines: {uncovered}')
"
```

**Example output:**
```
lib/atomic_fi/account_holder_context.ex: 163/166 = 98.2%
Uncovered lines: [235, 277, 315]
```

---

### Step 5: View Uncovered Code

Read the uncovered lines to understand what needs tests:

```bash
sed -n '230,240p' lib/atomic_fi/<module>.ex
sed -n '273,282p' lib/atomic_fi/<module>.ex
```

**Common uncovered patterns:**
- **Error paths**: `{:error, reason}` branches, changeset failures
- **Edge cases**: nil checks, empty lists, RLS-rejected queries
- **Pattern matching**: different function heads (e.g. `%AccountHolderRequest{} =` vs `%AccountHolder{} =`)
- **Guard clauses**: `when is_binary(id)`, `when type in [:individual, :business]`

---

### Step 6: Create TODO List

Use TodoWrite to track uncovered lines:

```elixir
[
  {content: "Check current coverage (98.2%)", status: "completed", activeForm: "..."},
  {content: "Add test for line 235 (error path)", status: "pending", activeForm: "..."},
  {content: "Add test for line 277 (edge case)", status: "pending", activeForm: "..."},
  {content: "Verify 100% coverage", status: "pending", activeForm: "..."}
]
```

---

### Step 7: Add Tests Iteratively

**CRITICAL PATTERNS** (atomic-fi conventions):

#### Test Error Paths

```elixir
test "returns error when tenant_id is missing on session", %{session: session} do
  bad_session = %{session | tenant_id: nil}
  attrs = %AccountHolderRequest{holder_type: "individual", status: "pending", risk_level: "low"}

  assert {:error, _} = AccountHolderContext.create_account_holder(bad_session, attrs)
end
```

#### Test Alternative Pattern Match Clauses

```elixir
# For: def get_account_holder!(session, id, opts \\ [])
#      def get_account_holder!(session, id, preload: preloads)

test "preloads associations when opts contain :preload", %{session: session, account_holder: ah} do
  result = AccountHolderContext.get_account_holder!(session, ah.id, preload: [:legal_entity])
  assert %Ecto.Association.NotLoaded{} != result.legal_entity
end
```

#### Test Edge Cases

```elixir
test "returns empty list when no account_holders exist for tenant", %{session: session} do
  assert [] = AccountHolderContext.list_account_holders(session)
end

test "RLS isolates account_holders across tenants", %{tenant_a_session: a, tenant_b_session: b} do
  insert(:account_holder, tenant_id: a.tenant_id)
  insert(:account_holder, tenant_id: b.tenant_id)

  assert length(AccountHolderContext.list_account_holders(a)) == 1
  assert length(AccountHolderContext.list_account_holders(b)) == 1
end
```

#### Test the Controller / Context Contract (no `Map.from_struct`)

Per `CLAUDE.md`: controllers pass typed structs directly to contexts.
Test from that angle:

```elixir
test "create_account_holder accepts an AccountHolderRequest struct directly", %{session: session} do
  request = %AccountHolderRequest{
    holder_type: "individual",
    status: "pending",
    kyc_status: "not_started",
    risk_level: "low",
    enabled_currencies: ["USD"]
  }

  assert {:ok, %AccountHolder{}} = AccountHolderContext.create_account_holder(session, request)
end
```

---

### Step 8: Verify Coverage After Each Test

After adding each test:

```bash
# Run tests
MIX_ENV=test mix test test/atomic_fi/<module>_test.exs --color 2>&1 | tee /tmp/test.txt

# Regenerate coverage
MIX_ENV=test mix coveralls.json -- test/atomic_fi/<module>_test.exs 2>&1 | tee /tmp/coverage.txt

# Check coverage increase
python3 -c "
import json
with open('cover/excoveralls.json') as f:
    data = json.load(f)
for sf in data['source_files']:
    if '<module>.ex' in sf['name'] and '<module>/' not in sf['name']:
        cov = sf['coverage']
        uncovered = [i+1 for i, c in enumerate(cov) if c == 0]
        total = len([c for c in cov if c is not None])
        covered = len([c for c in cov if c and c > 0])
        print(f'Coverage: {100*covered/total:.1f}% ({covered}/{total})')
        if uncovered:
            print(f'Still uncovered: {uncovered}')
        else:
            print('100% COVERAGE ACHIEVED!')
"
```

---

### Step 9: Reach 100% Coverage

Repeat Steps 7-8 until all lines are covered, then re-run the full suite
to confirm no regression:

```bash
MIX_ENV=test mix coveralls 2>&1 | tail -10
```

The headline `[TOTAL] xx.x%` should be ≥ the previous baseline.

---

## Quick Reference: Python Coverage Commands

```bash
# Coverage stats for module
python3 -c "
import json
with open('cover/excoveralls.json') as f:
    data = json.load(f)
for sf in data['source_files']:
    if 'MODULE.ex' in sf['name'] and 'MODULE/' not in sf['name']:
        cov = sf['coverage']
        total = len([c for c in cov if c is not None])
        covered = len([c for c in cov if c and c > 0])
        uncovered = [i+1 for i, c in enumerate(cov) if c == 0]
        print(f'Coverage: {100*covered/total:.1f}%')
        print(f'Uncovered: {uncovered}')
"

# List all atomic-fi modules with coverage < 100%
python3 -c "
import json
with open('cover/excoveralls.json') as f:
    data = json.load(f)
for sf in sorted(data['source_files'], key=lambda x: x['name']):
    if not sf['name'].startswith('lib/atomic_fi'): continue
    cov = sf['coverage']
    total = len([c for c in cov if c is not None])
    if total == 0: continue
    covered = len([c for c in cov if c and c > 0])
    pct = 100*covered/total
    if pct < 100:
        print(f'{pct:5.1f}% {sf[\"name\"]}')"
```

---

## Common Issues

### Issue 1: Coverage Unchanged After Adding Test

**Causes:**
- Test doesn't execute the target code path (wrong RLS scope, wrong tenant, missing preload)
- Test setup doesn't trigger the guard / pattern you expect

**Solution:** Trace the test with `--trace`:
```bash
MIX_ENV=test mix test test/atomic_fi/<module>_test.exs:<line> --trace --color
```

### Issue 2: Private Function Uncovered

**Cause:** No public function calls the private function with those arguments.

**Solution:** Call public function with inputs that trigger the private function path. Don't make it public just for coverage.

### Issue 3: Pattern Matching Order (Struct vs Map)

**Problem:** A generic map pattern like `%{field: value}` matches BEFORE a struct pattern because structs ARE maps.

```elixir
# ❌ WRONG ORDER - struct pattern is unreachable
case data do
  %{id: id} when is_binary(id) -> id           # This matches %AccountHolder{} too!
  %AccountHolder{id: id} when is_binary(id) -> id   # Never reached
  _ -> nil
end

# ✅ CORRECT ORDER - struct patterns FIRST
case data do
  %AccountHolder{id: id} when is_binary(id) -> id   # Struct first
  %{id: id} when is_binary(id) -> id           # Generic map fallback
  _ -> nil
end
```

**Solution:** Always put struct-specific patterns BEFORE generic map patterns.

### Issue 4: Unreachable Defensive Code

**Problem:** Code that handles impossible states (FK constraints, RLS-filtered collections, etc.) cannot be tested.

**Examples specific to atomic-fi:**
- Nil checks after RLS narrows the query to current tenant
- Error handlers for records that wouldn't pass the OpenApiSpex `cast/3` step
- Fallbacks where `def_with_rls_and_logging` already raised on missing session

**Solution:** Use `coveralls-ignore` comments and throw exceptions (see Defensive Coding Patterns below).

### Issue 5: Multi-line Logger Call Attribution (excoveralls artifact)

**Problem:** excoveralls inconsistently attributes individual lines of a multi-line
`Logger.info` / `Logger.warning` / `Logger.error` call (especially its keyword args
or body) to the tests that execute it. Lines that ARE exercised by existing tests
can still show as uncovered (hit count `0`) in the JSON report.

**Diagnostic signature:**
- Uncovered lines are `msg:`, `reason:`, or other keyword-arg continuations of a
  `Logger.*` call, OR the body of a small helper function called from within such
  a Logger call.
- Running just the test file that exercises the path and re-parsing
  `cover/excoveralls.json` shows the Logger call site with a mix of hit counts:
  some args `1`, some `None`, some `0`. That "None" next to a `1` in the same
  Logger call is the artifact.
- Writing additional tests DOES NOT flip these lines to covered.

**Why it happens:** excoveralls per-line AST-position instrumentation sometimes
collapses several source lines into a single AST span for multi-line macro calls.
On atomic-fi this surfaces especially around `def_with_rls_and_logging` because
that macro wraps each context function in a Logger call.

**Before concluding it's an artifact — verify:**

1. The same code path IS exercised by at least one existing test — run that test
   with `--trace` to confirm the Logger message emits.
2. Running the test in isolation, re-parse `cover/excoveralls.json` and look at
   the hit counts for the surrounding lines of the Logger call. If the function
   head OR at least one kwarg line shows `> 0`, the call IS being executed.
3. If the path is NOT exercised by any test, this is NOT an artifact — it's a
   genuinely untested branch and needs a real test (see Issue 1).

**Solution once verified:**

Wrap the Logger call (or the tiny helper it delegates to) in
`coveralls-ignore-start` / `coveralls-ignore-stop`, with a justification:

```elixir
# coveralls-ignore-start: multi-line Logger keyword-args excoveralls artifact — path tested via test/atomic_fi/account_holder_context_test.exs:123
Logger.warning(
  op: "create_account_holder",
  error_code: :screening_failed,
  resource_type: "account_holder",
  reason: reason
)
# coveralls-ignore-stop
```

The justification is load-bearing — points the next maintainer at the
authoritative test so they don't repeat the investigation.

---

## Defensive Coding Patterns

**CRITICAL: For database failures and impossible states, follow this pattern:**

1. **Raise exceptions** instead of elegant error handling (return values)
2. **Log the error** before raising
3. **Add coveralls-ignore** around the defensive code

**Why?**
- These paths represent genuine failures that should crash and alert
- Elegant handling masks real issues in production
- Tests cannot (and should not) exercise impossible paths
- Logging ensures failures are traceable in production

**Pattern:**

```elixir
# coveralls-ignore-start: Defensive - tenant_id is set by ApiAuthentication plug on every request
defp ensure_tenant(nil) do
  Logger.error("Unexpected nil tenant_id - ApiAuthentication should prevent this")
  raise "Unexpected nil tenant_id"
end
# coveralls-ignore-stop

# coveralls-ignore-start: Defensive - blocklist entries are filtered by warmup before lookup
defp lookup_entry(_session, nil) do
  Logger.error("BlocklistCache lookup with nil key - warmup invariant violated")
  raise "BlocklistCache invariant violated"
end
# coveralls-ignore-stop
```

**When to Use:**
- Nil checks after RLS / auth plug invariants
- Error handlers for collections already filtered upstream
- Pattern match branches that schema validation prevents

**When NOT to Use:**
- Actual error paths that CAN occur (Watchman timeout, network error, validation failure)
- Business logic branches that are just untested
- Code that should be deleted (dead code)

---

## Success Criteria

- [ ] Targeted module ≥ 95% coverage (or 100% for new code)
- [ ] All tests passing
- [ ] TODO list marked complete
- [ ] `mix coveralls` headline ≥ previous baseline

---

## Related Commands

- `/qa:quality-checks` - Run all quality checks before committing
- `/qa:fix-failing-tests` - Diagnose and fix test failures
- `/qa:check-api-quality` - Structural drift checker for controllers
- `/dev:create-rest-api` - Create REST API with tests
