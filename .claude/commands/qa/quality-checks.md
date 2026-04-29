---
name: quality-checks
description: Run all code quality checks before committing
when_to_use:
  - Before creating a pull request
  - After making significant changes
  - Pre-commit verification (REQUIRED)
related_guides:
  - guides/cheatsheet/quality_gates.cheatmd
  - guides/cheatsheet/developer_guide.cheatmd
related_commands:
  - /qa:fix-failing-tests (Step 6a/6b failures)
  - /qa:increase-test-coverage (Step 6c coverage gaps)
  - /qa:review (multi-agent review after all gates pass)
---

# Run Quality Checks Before Committing

Run all quality checks that must pass before committing code to the repository.

## Usage

```
/quality-checks
```

Alternatively, you can use the Makefile command:
```bash
make quality
```

## Critical Gate Rule

**Each step is a hard gate. If a step fails, STOP immediately — do NOT proceed to the next step.**

1. Collect ALL failing files/issues from the failing step
2. Fix **one file at a time** using the appropriate skill (`/qa:fix-failing-tests`, `/qa:increase-test-coverage`)
3. Re-run the **same step** to confirm it passes
4. Only then move to the next step

No excuses. No skipping ahead. No fixing-while-running.

## Code Change Permission Rule

**When any quality check (credo, compilation warning, sobelow, mix doctor) flags an issue in `lib/` code, do NOT fix it autonomously.** Instead:

1. Show the user the exact issue (file, line, message)
2. Present the available fix options (e.g. `@doc false` vs `defp` vs suppress)
3. Wait for the user to choose
4. Only then apply the chosen fix

This applies to ALL quality steps below. The user's code design decisions (public vs private, naming, structure) are intentional — a "quick fix" for a linter warning can break tests or violate architectural intent.

**Test files (`test/`)** may be fixed without asking when the fix is mechanical (e.g. updating arity in a test call to match a changed function signature).

---

## Instructions

Run the following checks in sequence. Each step must pass before the next begins. These mirror the exact CI steps in `.github/workflows/code-quality.yml` and `.github/workflows/test.yml`.

### Step 1: Compilation Check (Zero Warnings)

```bash
mix compile --warnings-as-errors
```

If this fails, fix all warnings before proceeding.

**Common issues:**
- Unused variables: Prefix with underscore `_unused_param`
- Missing type specs: Add `@spec` where indicated
- Deprecated functions: Update to current API

### Step 2: Code Formatting

```bash
mix format --check-formatted
```

If this fails, run `mix format` to auto-format, then proceed.

### Step 3: Code Quality — Full Codebase (Warnings Only)

```bash
MIX_ENV=test mix credo --strict --only warning
```

This runs across the full codebase but only surfaces `warning`-level issues. Fix any reported before proceeding.

**Common issues:**
- Long functions: Refactor into smaller functions (max 30 lines)
- Missing documentation: Add `@moduledoc` and `@doc`
- Complexity: Simplify conditional logic

### Step 4: Code Quality — Changed Files Only (CI-equivalent)

```bash
./scripts/credo_changed.sh
```

This runs `mix credo diff --from-git-merge-base origin/develop --strict` — exactly what CI runs. It only flags issues **introduced by the current branch** relative to `develop`.

**When issues are reported, reason about them before fixing:**
- Is the flagged file one you modified in this session? → **Fix it immediately**
- Is it a pre-existing issue in a file you didn't touch? → **Note it** but it should not appear here since the diff scope covers only changed files — if it does appear, it means your changes triggered it indirectly (e.g. a `use` macro expansion). Still fix it.
- Never dismiss a credo issue as "pre-existing" — if the diff surfaces it, it counts

**Common checks enforced:**
- `LazyTermInSpec`: Replace `term()` with real types like `{atom(), String.t()}`
- `RequireDocOnPublicFunction`: Add `@doc` or `@doc false` to public functions
- `StubBoundaryViolation`: Remove forbidden Mimic stubs on internal platform modules

### Step 5: Security Scan (Sobelow)

```bash
mix sobelow --config
```

Fix any security vulnerabilities before proceeding.

**Common issues:**
- SQL injection: Use parameterized queries
- XSS vulnerabilities: Proper output escaping
- Insecure dependencies: Update vulnerable packages

### Step 6a: Core Test Suite

Runs all tests **except** `feature` (browser) and `heavy` (>500ms) tagged tests. Uses the `test.core` mix alias.

```bash
# 1. Reset test database (only if schema/migration changes, otherwise skip)
MIX_ENV=test mix ecto.reset

# 2. Warmup — verify the test suite compiles and loads cleanly (runs 0 tests)
MIX_ENV=test mix test --only non_existing_tag

# 3. Core tests (excludes feature + heavy)
MIX_ENV=test mix test.core --color
```

**If tests fail:** Collect ALL failing test files first, then use `/qa:fix-failing-tests` — one file at a time.

### Step 6b: DDLs Test Suite

Runs only `heavy` and `do_not_shard` tagged tests (DDL migrations, complex workflows, regulated CRUD). Uses the `test.ddls` mix alias.

```bash
MIX_ENV=test mix test.ddls --color
```

These tests are expected to be slow (>500ms). Each must have `@moduletag :heavy` or `@tag :heavy` with an approved `speed:` reason.

### Step 6c: Coverage Check (Optional — run when CI requires it)

```bash
# Core tests with coverage
MIX_ENV=test mix test.core.cover

# DDLs tests with coverage
MIX_ENV=test mix test.ddls.cover
```

Verify:
- Every `.ex` file you touched has 95%+ coverage (use `mix coveralls.json` for per-file detail)
- Overall coverage above 90% (minimum acceptable)

**If coverage low:** Use `/qa:increase-test-coverage`

### Step 7: Stub Boundary Check

Verify test files only mock external boundaries. Run:

```bash
grep -rn "Mimic\.\(copy\|stub\|expect\)(Platform\." test/ --include="*.exs" \
  | grep -v "AtomicFi.DatalakeRepo" \
  | grep -v "AtomicFi.RegulatedDatalakeRepo"
```

If any results appear, review each one. Only these external boundaries may be stubbed with Mimic:
- `AtomicFi.DatalakeRepo` — repo routing
- `AtomicFi.RegulatedDatalakeRepo` — regulated repo routing
- `ExAws` — AWS SDK
- `System` — system commands

Also allowed: `Req.Test.stub` (HTTP boundary — any module) and `Mox.stub(ExAws.Mock, ...)` (AWS SDK via the Mox-wired `@s3_client`).

**FORBIDDEN:** Mimic on any other `AtomicFi.*` module (e.g., `AtomicFi.Messages`, `AtomicFi.Templates`, `AtomicFi.AgenticWorkflows`, **`AtomicFi.CloudStorageProtocol`**). Cloud storage must be exercised through the real protocol dispatch with `Mox.stub(ExAws.Mock, :request/:request!/:stream!, ...)` at the AWS boundary — not by stubbing the protocol itself. Use real implementations with `setup :setup_healthcare_context` (or `setup_core_banking_context`, `setup_payment_risk_context`, `setup_alvera_context`, `setup_trading_context`, `setup_accounts_receivable_context`, `setup_service_commerce_context` — one per supported domain) instead.

### Step 8: Check for Anti-Patterns

**Direct datalake-repo calls outside `with_dynamic_repo`:**

All datalake persistence routes through `AtomicFi.DatalakeRepo` / `AtomicFi.RegulatedDatalakeRepo` inside a `with_dynamic_repo(repo_pid, …)` block — there are no industry-specific datalake repo modules in `lib/`. Context functions that call `AtomicFi.DatalakeRepo.all/insert/update/delete` without having set up dynamic routing will crash at runtime; surface that statically:

```bash
# Callers of AtomicFi.(Regulated)DatalakeRepo must appear inside a with_dynamic_repo block
grep -rn "Platform\.\(Regulated\)\?DatalakeRepo\.\(all\|insert\|update\|delete\|one\|get\|get!\|transaction\)" lib/atomic_fi/ --include="*.ex" \
  | grep -v "with_dynamic_repo" \
  | grep -v "_repo.ex" \
  | grep -v "datalakes/migration"
```

Any result is a bug — wrap the call in `with_dynamic_repo(get_datalake_repo(datalake), AtomicFi.DatalakeRepo) do … end`.

**Missing checksum protocol implementations:**
```bash
# Check if any new datalake schemas are missing ChecksumProtocol
find lib/platform -name "protocols.ex" -type f
```

Verify all datalake resources have `protocols.ex` files implementing ChecksumProtocol.

**No PATCH endpoints in the API routes** (platform-wide policy — see [cheatsheet/developer_guide.cheatmd § REST API Endpoints](../../../guides/cheatsheet/developer_guide.cheatmd#rest-api-endpoints)):
```bash
# Explicit `patch "..." declarations
grep -nE '^\s*patch\s+"' lib/atomic_fi_api/routes.ex

# `resources ... :update` which secretly generates both PUT and PATCH
grep -nE 'resources.*:update' lib/atomic_fi_api/routes.ex
```

Both greps must return **zero results**. If either is non-empty, the PR is
blocked — convert to `resources ... only: [...]` (without `:update`) plus an
explicit `put "/.../:id"` for replacement. Every update endpoint must be PUT
with a full resource body.

**No `Mapper.to_map` or `request_to_attrs` in controllers:**
```bash
grep -rnE 'Mapper\.to_map|request_to_attrs' lib/atomic_fi_api/controllers/
```

Must return zero results. Controllers pass the Request struct directly to
context functions; conversion happens via the shadowed `cast/4` inside the
schema changeset.

### Step 9: Documentation Coverage (mix doctor)

```bash
mix doctor
```

Verify:
- All modules pass (0 failed)
- Overall doc coverage ≥ 85%
- Overall spec coverage ≥ 85%
- Overall moduledoc coverage = 100%

If modules fail:
- **Missing `@spec`:** Add type specs to public functions. Read the module's test file first to understand return types.
- **Missing `@doc`:** Add concise documentation to public functions.
- **Missing `@moduledoc`:** Add module-level documentation or `@moduledoc false` for internal/private modules.

**DO NOT add files to `.doctor.exs` ignore list** unless they are dead Petal Pro template code with no active routes or imports.

### Step 9b: Test Coverage Declaration (Top-Level Contexts)

Every modified file matching `lib/atomic_fi/*.ex` (top-level only — not nested modules) with a real `@moduledoc` MUST declare a `## Test Coverage` section listing the exact test files that exercise it. `@moduledoc false` modules are exempt.

**Why:** Top-level `lib/atomic_fi/*.ex` files are the business-logic context boundaries. Their tests are often decomposed across context tests, LiveView integration tests, and component tests. `mix coveralls.json` requires all relevant test files on the CLI — without a central reference in the moduledoc itself, CI scripts and reviewers cannot know which tests to run for accurate coverage.

**Pattern:**

```elixir
defmodule AtomicFi.Datalakes do
  @moduledoc """
  Context for datalake management.

  ## Test Coverage

      mix coveralls.json -- \\
        test/atomic_fi/datalakes_test.exs \\
        test/atomic_fi_web/live/datalake_live/index_test.exs
  """
end
```

**Check:**

```bash
for f in $(git diff --name-only HEAD | grep -E '^lib/atomic_fi/[^/]+\.ex$'); do
  grep -q '@moduledoc false' "$f" && continue
  grep -q '^\s*## Test Coverage' "$f" || echo "FAIL: $f missing ## Test Coverage section in @moduledoc"
done
```

**Rationale for top-level-only scope:** Nested modules (schemas, embeds, workers) are exercised through their parent context — the parent's `## Test Coverage` section lists the integration tests that cover them. Enforcing on every `lib/**/*.ex` would demand the same section on schemas/embeds, which would add noise without new signal.

### Step 11: Ignore-File Guard

Any `.ex` file you edited must have coverage in **at least one** of the two test suites. A file is only a problem if it appears in the skip list of **both** `coveralls.quick.json` AND `coveralls.heavy.json` — being skipped in just one is fine since the other suite still covers it.

There are **three** coveralls configs:

- `coveralls.json` — base config (used by `mix coveralls.json`)
- `coveralls.quick.json` — core tests (`mix test.core.cover`)
- `coveralls.heavy.json` — DDLs tests (`mix test.ddls.cover`)

```bash
# Check for files skipped in BOTH quick and heavy (no coverage at all)
for f in $(git diff --name-only HEAD); do
  in_quick=$(grep -q "$(echo $f | sed 's/\//\\\//g')" coveralls.quick.json 2>/dev/null && echo "yes" || echo "no")
  in_heavy=$(grep -q "$(echo $f | sed 's/\//\\\//g')" coveralls.heavy.json 2>/dev/null && echo "yes" || echo "no")
  if [ "$in_quick" = "yes" ] && [ "$in_heavy" = "yes" ]; then
    echo "FAIL: $f is skipped in BOTH coveralls.quick.json AND coveralls.heavy.json — no coverage!"
  fi
done

# Check .doctor.exs ignore_paths
for f in $(git diff --name-only HEAD); do
  grep -q "$(basename $f .ex | sed 's/\./\\\\./g')" .doctor.exs 2>/dev/null && echo "FAIL: $f is in .doctor.exs ignore_paths"
done
```

If a file you edited is skipped in **both** coveralls configs, remove it from at least one — edited files must have test coverage in at least one suite. Files in `.doctor.exs` ignore list must be removed entirely.

## Summary Report

After all checks pass, provide a summary:

```
Quality Checks Summary:
- Compilation:        PASS (0 warnings)
- Formatting:         PASS
- Credo (full):       PASS
- Credo (changed):    PASS
- Sobelow:            PASS
- Core tests:         PASS (X tests, 0 failures)
- DDLs tests:         PASS (Y tests, 0 failures)
- Coverage:           PASS (Z% overall)
- Stub boundaries:    PASS
- Anti-patterns:      PASS
- Doc coverage:       PASS (mix doctor)
- Ignore-file guard:  PASS

Ready to commit!
```

## Troubleshooting

### Compilation Warnings

```elixir
# Fix unused variable
def function(_unused_param), do: :ok

# Fix missing type spec
@spec function(integer()) :: :ok
def function(number), do: :ok
```

### Credo Issues

**Long function:**
```elixir
# BEFORE: 50-line function
def long_function(params) do
  # ... 50 lines
end

# AFTER: Refactored
def long_function(params) do
  validate_params(params)
  |> process_data()
  |> save_results()
end
```

**Missing moduledoc:**
```elixir
defmodule AtomicFi.Healthcare.Patients do
  @moduledoc """
  Context for managing Patient resources in healthcare datalakes.
  """
  # ...
end
```

### Coverage Below 90%

```bash
# See uncovered lines
mix coveralls.detail --filter lib/atomic_fi/path/to/file.ex

# Use increase-test-coverage command
/qa:increase-test-coverage
```

### Anti-Pattern: Direct Repo Usage

```elixir
# WRONG - Using industry-specific repo in lib/ code
def list_patients(%Datalake{} = datalake) do
  HealthcareDatalakeRepo.all(Patient)  # ❌
end

# CORRECT - Using AtomicFi.DatalakeRepo with with_dynamic_repo
def list_patients(%Datalake{} = datalake) do
  repo_pid = AtomicFi.Datalakes.get_datalake_repo(datalake)
  
  with_dynamic_repo(repo_pid, AtomicFi.DatalakeRepo) do
    Patient
    |> preload(^@patient_preloads)
    |> AtomicFi.DatalakeRepo.all()  # ✅
  end
end
```

## Related Commands

- `/qa:fix-failing-tests` - If Step 6a or 6b fails
- `/qa:increase-test-coverage` - If coverage below 90%

