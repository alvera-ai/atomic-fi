# Increase Code Coverage to 100%

Iteratively increase test coverage for a specific module to reach 100% coverage.

## Usage

```
/increase-coverage <module_path>
```

**Example:**
```
/increase-coverage lib/payment_compliance_platform/user_context.ex
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

### Step 2: Generate Targeted Coverage Report

Run the specific test file with coverage to generate JSON:

```bash
# Generate JSON coverage for specific test file
MIX_ENV=test mix coveralls.json -- test/payment_compliance_platform/<module>_test.exs
```

This creates `cover/excoveralls.json` with detailed line-by-line coverage.

---

### Step 3: Get Coverage Stats with Python

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
lib/payment_compliance_platform/user_context.ex: 163/166 = 98.2%
Uncovered lines: [235, 277, 315]
```

---

### Step 4: View Uncovered Code

Read the uncovered lines to understand what needs tests:

```bash
# View specific uncovered lines (adjust numbers from Step 3)
sed -n '230,240p' lib/payment_compliance_platform/<module>.ex
sed -n '273,282p' lib/payment_compliance_platform/<module>.ex
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
  {content: "Add test for line 235 (success path)", status: "pending", activeForm: "..."},
  {content: "Add test for line 277 (existing record)", status: "pending", activeForm: "..."},
  {content: "Verify 100% coverage", status: "pending", activeForm: "..."}
]
```

---

### Step 6: Add Tests Iteratively

**CRITICAL PATTERNS:**

#### Test Error Paths

```elixir
test "handles error gracefully", %{...} do
  # Test with invalid data or edge case
  assert {:error, changeset} = Context.create_resource(invalid_attrs)
  assert "can't be blank" in errors_on(changeset).field_name
end
```

#### Test Alternative Pattern Match Clauses

```elixir
# For: defp process(nil), do: {:error, :not_found}
#      defp process(%Resource{} = r), do: {:ok, r}

test "handles nil input", %{...} do
  assert {:error, :not_found} = Context.process_resource(nil)
end

test "processes valid resource", %{...} do
  resource = insert(:resource)
  assert {:ok, ^resource} = Context.process_resource(resource)
end
```

---

### Step 7: Verify Coverage After Each Test

After adding each test:

```bash
# Run tests
MIX_ENV=test mix test test/payment_compliance_platform/<module>_test.exs

# Regenerate coverage
MIX_ENV=test mix coveralls.json -- test/payment_compliance_platform/<module>_test.exs

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
MIX_ENV=test mix coveralls.json -- test/payment_compliance_platform/<module>_test.exs

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
MIX_ENV=test mix test test/payment_compliance_platform/<module>_test.exs:<line> --trace
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
  %{id: id} when is_binary(id) -> id           # This matches User too!
  %User{id: id} when is_binary(id) -> id       # Never reached
  _ -> nil
end

# ✅ CORRECT ORDER - struct patterns FIRST
case data do
  %User{id: id} when is_binary(id) -> id       # Check struct first
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

**Solution:** Use `coveralls-ignore` comments and throw exceptions (see Defensive Coding Patterns below).

---

## Defensive Coding Patterns

**CRITICAL: For DB failures and impossible states, follow this pattern:**

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

# coveralls-ignore-start: Defensive - filtered before call
defp refund_entity(%Entity{required_field: nil} = entity) do
  Logger.error("Cannot process entity #{entity.id} - missing required_field")
  raise "Entity missing required_field"
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

- `/quality-checks` - Run all quality checks before committing
- `/create-rest-api` - Create REST API with tests
- `/create-integration-test` - Create integration tests
