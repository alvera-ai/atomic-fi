---
name: increase-test-coverage
description: Iteratively lift a specific module's test coverage toward 100% by targeting its test files with coveralls
when_to_use:
  - Boosting coverage on a newly implemented module before PR
  - Closing gaps after a refactor changed branches without updating tests
  - Pre-merge coverage audit of a high-risk context
related_guides:
  - guides/cheatsheet/quality_gates.cheatmd
related_commands:
  - /qa:fix-failing-tests (if a new test fails — diagnose before continuing)
  - /dev:optimize-tests-with-preseeded-data (if the coverage run is slow)
  - /qa:quality-checks (run before committing — REQUIRED)
---

# Increase Code Coverage to 100%

Iteratively lift a specific module's coverage toward 100%. Runs a
**module-scoped** coveralls subset (not the full suite) — this
sidesteps slow DDL/heavy tests by design, so no tiered-test gymnastics
are needed.

## Usage

```
/qa:increase-test-coverage <module_path>
```

**Example:**
```
/qa:increase-test-coverage lib/atomic_fi/healthcare/patients.ex
```

## Instructions

Follow these steps to systematically increase coverage to 100%.

---

### Step 1: Verify Module Not Excluded

Check `coveralls.json` to ensure the target module is NOT in `skip_files`:

```bash
cat coveralls.json | grep -i "$(basename <module_path> .ex)"
```

If found in `skip_files`, remove it before proceeding.

---

### Step 2: Curate Test File List in Moduledoc

Check if the target module already has a `## Test Coverage` section in its
`@moduledoc`. If it does, use those globs directly and skip to Step 3.

If not, **curate** the list — don't blindly grep. A context module referenced by
80 test files doesn't need all 80; most are downstream consumers that don't
exercise the target's code paths. Apply judgment:

**Step 2a: Identify direct test files**

These test the module's public API directly (context functions, schema
changesets, worker perform/1). Use globs where possible:

    test/atomic_fi/<module>/*_test.exs
    test/atomic_fi/<module>/workers/*_test.exs

**Step 2b: Identify integration/lifecycle tests (1 degree deeper)**

These are end-to-end tests that drive the module's code through realistic
flows (e.g., athena lifecycle tests exercise DAC pagination, row processing,
MDM resolution). Include them — they cover the deep pipeline paths that
unit tests miss.

    test/atomic_fi/<module>/athena/*_test.exs
    test/atomic_fi/<module>/open_banking/*_test.exs

**Step 2c: Identify HTTP/controller tests**

If the module is called by a controller, include the controller's test files:

    test/atomic_fi_api/controllers/<related>_test.exs

**Step 2d: Write the curated list into the module's `@moduledoc`**

Add a `## Test Coverage` section at the end of the `@moduledoc` with the
curated globs. This persists the judgment call for future coverage runs:

```elixir
@moduledoc """
...existing docs...

## Test Coverage

    Direct (unit + context tests):
        test/atomic_fi/data_activation_clients/*_test.exs
        test/atomic_fi/data_activation_clients/workers/*_test.exs

    Integration (lifecycle + flow tests):
        test/atomic_fi/data_activation_clients/athena/*_test.exs
        test/atomic_fi/data_activation_clients/open_banking/*_test.exs

    HTTP (controller tests):
        test/atomic_fi_api/controllers/data_activation_client_*_test.exs
"""
```

**Judgment rules:**

- Include test files that call the module's public functions directly
- Include lifecycle/integration tests that drive the module's code through
  realistic end-to-end flows
- Exclude downstream consumer tests that only reference the module's structs
  (e.g., healthcare resource tests that import a DAC factory but don't call
  DAC context functions)
- Exclude LiveView tests unless they specifically test module functionality
- Use globs (`*_test.exs`) to keep the list maintainable

---

### Step 3: Generate Targeted Coverage Report

Expand the globs from the moduledoc's `## Test Coverage` section and run
coveralls. Back up the JSON so partial re-runs don't overwrite the baseline:

```bash
# Generate JSON coverage with curated test files
zsh -l -c 'source ~/.zshrc && MIX_ENV=test mix coveralls.json --color -- <expanded_glob_1> <expanded_glob_2> ... 2>&1 | tee /tmp/coverage.txt'

# Back up the baseline
cp cover/excoveralls.json /tmp/<module>-excoveralls-backup.json
```

This creates `cover/excoveralls.json` with detailed line-by-line coverage.

---

### Step 4: Get Coverage Stats with Python

Use Python to parse coverage (more reliable than jq with shell escaping):

```bash
# Get coverage stats for specific module
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
lib/atomic_fi/healthcare/patients.ex: 163/166 = 98.2%
Uncovered lines: [235, 277, 315]
```

---

### Step 4: View Uncovered Code

Read the uncovered lines to understand what needs tests:

```bash
# View specific uncovered lines (adjust numbers from Step 3)
sed -n '230,240p' lib/atomic_fi/<module>.ex
sed -n '273,282p' lib/atomic_fi/<module>.ex
```

**Common uncovered patterns:**
- **Error paths**: `{:error, reason}` branches
- **Edge cases**: nil checks, empty lists
- **Pattern matching**: Different function heads
- **Guard clauses**: `when` conditions

---

### Step 5: Create TODO List

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

### Step 6: Add Tests Iteratively

**CRITICAL PATTERNS:**

#### Test Error Paths

```elixir
test "returns error when datalake invalid", %{user: user, client: client} do
  invalid_datalake = %AtomicFi.Datalakes.Datalake{
    id: Ecto.UUID.generate(),
    db_schema: "nonexistent"
  }
  attrs = %{status: :active, gender: :male}

  assert {:error, _reason} = Patients.create_patient(invalid_datalake, user, client, nil, attrs)
end
```

#### Test Alternative Pattern Match Clauses

```elixir
# For: def get_patient(%Datalake{} = datalake, id)
#      def get_patient(%Datalake{} = datalake, nil)

test "handles nil ID gracefully", %{datalake: datalake} do
  assert_raise Ecto.NoResultsError, fn ->
    Patients.get_patient!(datalake, nil)
  end
end
```

#### Test Edge Cases

```elixir
test "returns empty list when no patients exist", %{datalake: datalake} do
  assert [] = Patients.list_patients(datalake)
end

test "handles large result sets", %{datalake: datalake} do
  for _i <- 1..100 do
    PublicHealthcareFactory.insert(:patient)
  end

  patients = Patients.list_patients(datalake)
  assert length(patients) == 100
end
```

---

### Step 7: Verify Coverage After Each Test

After adding each test:

```bash
# Run tests
zsh -l -c 'source ~/.zshrc && MIX_ENV=test mix test test/atomic_fi/<module>_test.exs --color 2>&1 | tee /tmp/test.txt'

# Regenerate coverage
zsh -l -c 'source ~/.zshrc && MIX_ENV=test mix coveralls.json --color -- test/atomic_fi/<module>_test.exs 2>&1 | tee /tmp/coverage.txt'

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

### Step 8: Reach 100% Coverage

Repeat Steps 6-7 until all lines are covered.

**Final verification:**

```bash
# Run full test suite for module
zsh -l -c 'source ~/.zshrc && MIX_ENV=test mix coveralls.json --color -- test/atomic_fi/<module>_test.exs 2>&1 | tee /tmp/coverage.txt'

# Confirm 100%
python3 -c "
import json
with open('cover/excoveralls.json') as f:
    data = json.load(f)
for sf in data['source_files']:
    if '<module>.ex' in sf['name'] and '<module>/' not in sf['name']:
        cov = sf['coverage']
        total = len([c for c in cov if c is not None])
        covered = len([c for c in cov if c and c > 0])
        pct = 100*covered/total
        print(f'{sf[\"name\"]}: {pct:.1f}%')
        assert pct == 100.0, f'Coverage is {pct}%, not 100%'
        print('SUCCESS: 100% coverage achieved!')
"
```

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

# List all modules with coverage < 100%
python3 -c "
import json
with open('cover/excoveralls.json') as f:
    data = json.load(f)
for sf in sorted(data['source_files'], key=lambda x: x['name']):
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
- Test doesn't execute the target code path
- Wrong conditions in test setup

**Solution:** Add debug output or trace the test:
```bash
zsh -l -c 'source ~/.zshrc && MIX_ENV=test mix test test/atomic_fi/<module>_test.exs:<line> --trace --color 2>&1 | tee /tmp/test.txt'
```

### Issue 2: Private Function Uncovered

**Cause:** No public function calls private function with those arguments

**Solution:** Call public function with inputs that trigger private function path

### Issue 3: Pattern Matching Order (Struct vs Map)

**Problem:** A generic map pattern like `%{field: value}` matches BEFORE a struct pattern because structs ARE maps.

**Example:**
```elixir
# ❌ WRONG ORDER - struct pattern is unreachable
case data do
  %{id: id} when is_binary(id) -> id           # This matches %Datalake{} too!
  %Datalake{id: id} when is_binary(id) -> id   # Never reached
  _ -> nil
end

# ✅ CORRECT ORDER - struct patterns FIRST
case data do
  %Datalake{id: id} when is_binary(id) -> id   # Check struct first
  %{id: id} when is_binary(id) -> id           # Generic map fallback
  _ -> nil
end
```

**Solution:** Always put struct-specific patterns BEFORE generic map patterns.

### Issue 4: Unreachable Defensive Code

**Problem:** Code that handles impossible states (FK constraints, filtered collections, etc.) cannot be tested.

**Examples:**
- Nil checks after FK constraint ensures non-null
- Error handlers for records filtered out before the call
- Fallbacks that DB queries prevent

**Solution:** Use `coveralls-ignore` comments and throw exceptions (see Defensive Coding Patterns below).

### Issue 5: Multi-line Logger Call Attribution (excoveralls artifact)

**Problem:** excoveralls inconsistently attributes individual lines of a multi-line
`Logger.info` / `Logger.warning` / `Logger.error` call (especially its keyword args
or body) to the tests that execute it. Lines that ARE exercised by existing tests
can still show as uncovered (hit count `0`) in the JSON report, even though running
the tests in isolation shows the AST node adjacent to them hitting `1`.

**Diagnostic signature:**
- Uncovered lines are `msg:`, `reason:`, or other keyword-arg continuations of a
  `Logger.*` call, OR the body of a small helper function called from within such
  a Logger call (e.g. `reject_reason: traverse_changeset_errors(changeset)`).
- Running just the test file that exercises the path and re-parsing `cover/excoveralls.json`
  shows the Logger call site with a mix of hit counts: some args `1`, some `None`,
  some `0`. That "None" next to a `1` in the same Logger call is the artifact.
- Writing additional tests DOES NOT flip these lines to covered — they're not
  attribution-addressable.

**Why it happens:** excoveralls relies on per-line AST-position instrumentation.
For multi-line Logger macros the macro expansion sometimes collapses several
source lines into a single AST span, so only one of them picks up the hit count;
the others get tagged as unmeasured. The exact mapping depends on the
Elixir/excoveralls version.

**Before concluding it's an artifact — verify:**

1. The same code path IS exercised by at least one existing test — run that test
   with `--trace` to confirm the Logger message gets emitted.
2. Running the test in isolation, re-parse `cover/excoveralls.json` and look at
   the hit counts for the surrounding lines of the Logger call. If the function
   head OR at least one kwarg line shows `> 0`, the call IS being executed.
3. If the path is NOT exercised by any test, this is NOT an artifact — it's a
   genuinely untested branch and needs a real test (see Issue 1).

**Solution once verified:**

Wrap the whole Logger call (or the tiny helper it delegates to) in
`coveralls-ignore-start` / `coveralls-ignore-stop`, with a justification that
points at the existing test that exercises the path:

```elixir
# coveralls-ignore-start: multi-line Logger keyword-args excoveralls artifact — path tested via test/atomic_fi/foo_test.exs:123
Logger.warning(
  op: "something",
  error_code: :some_code,
  resource_type: template.resource_type,
  reason: reason
)
# coveralls-ignore-stop
```

The justification is load-bearing — it tells the next maintainer the code IS
tested so they don't repeat the investigation, and points at the authoritative
test file + line so they can verify the claim.

**When NOT to use this pattern:**

- If no existing test exercises the path, do NOT use this ignore — write a real
  test (see Issue 1).
- If the path is genuinely unreachable (FK constraint, filtered collection, etc.),
  use the Defensive Coding Patterns below instead — that justification is
  different and should not claim "tested via...".

---

## Defensive Coding Patterns

**CRITICAL: For database failures and impossible states, follow this pattern:**

1. **Throw exceptions** instead of elegant error handling (return values)
2. **Log the error** before throwing
3. **Add coveralls-ignore** around the defensive code

**Why?**
- These paths represent genuine failures that should crash and alert
- Elegant handling masks real issues in production
- Tests cannot (and should not) exercise impossible paths
- Logging ensures failures are traceable

**Pattern:**

```elixir
# coveralls-ignore-start: Defensive - FK constraint ensures non-null
defp process_record(nil) do
  Logger.error("Unexpected nil record - FK constraint should prevent this")
  raise "Unexpected nil record"
end
# coveralls-ignore-stop

# coveralls-ignore-start: Defensive - patients are filtered before call
defp update_patient(%Patient{status: nil} = patient) do
  Logger.error("Patient #{patient.id} has nil status - unexpected state")
  raise "Patient missing status"
end
# coveralls-ignore-stop
```

**Comment Format:**
```elixir
# coveralls-ignore-start: Defensive - <reason why this is unreachable>
<defensive code>
# coveralls-ignore-stop
```

**When to Use:**
- Nil checks after database FK constraints
- Error handlers for already-filtered collections
- Pattern match branches that DB queries prevent

**When NOT to Use:**
- Actual error paths that CAN occur (user input validation, network timeouts)
- Business logic branches that are just untested
- Code that should be deleted (dead code)

---

## Success Criteria

- [ ] 100% coverage verified via Python/JSON
- [ ] All tests passing
- [ ] TODO list marked complete

---

## Related Commands

- `/qa:quality-checks` - Run all quality checks before committing
- `/qa:fix-failing-tests` - Diagnose and fix test failures
- `/dev:create-rest-api` - Create REST API with tests
- `/create-integration-test` - Create integration tests
