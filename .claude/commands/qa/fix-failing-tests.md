---
name: fix-failing-tests
description: Systematic workflow to debug and fix failing tests
when_to_use:
  - Tests failing after changes
  - Systematic test debugging needed
  - Coverage regression or test suite issues
related_guides:
  - guides/cheatsheet/quality_gates.cheatmd
  - guides/core-infra/datalakes.md
related_commands:
  - /qa:increase-test-coverage (run before committing)
  - /qa:quality-checks (run before committing - REQUIRED)
---
# Recipe: Fix Failing Tests

Systematic workflow for debugging and fixing failing tests — oriented
around the tiered test suite (`mix test.core` for the fast inner
loop, `mix test.ddls` for the slow DB/migration tier).

**When to use:**
- Tests failing after refactoring or dependency updates
- Random test failures
- New tests failing during development

**Related guides:**
- [guides/cheatsheet/quality_gates.cheatmd](../../../guides/cheatsheet/quality_gates.cheatmd) — three-tier quality model + commit gate
- [guides/core-infra/datalakes.md](../../../guides/core-infra/datalakes.md) — multi-repo + migration patterns

---

## The core loop (this is the workflow — don't skip steps)

```
  mix ecto.reset
       │
       ▼
  mix test.core               ← discover failures
       │
       ▼
  mix test.core --failed      ← iterate; fix ONE file at a time
       │                         (repeat until this is green)
       ▼
  mix test.core               ← full re-run; confirm nothing else broke
       │
       ├─ green ──► done. touch mix test.ddls ONLY if:
       │             • the user explicitly asks, or
       │             • something is still broken that core doesn't see
       │
       └─ red ────► back to mix test.core --failed
```

**Do not touch `mix test.ddls` unless explicitly told to, or unless
`mix test.core` is fully green and something is still red.** The ddls
tier is slow and covers migration / heavy-DDL scenarios; running it
while core is still iterating wastes minutes per cycle.

If you do escalate to `test.ddls`, the same loop applies:

```
  mix test.ddls --max-cases 4
       │
       ▼
  mix test.ddls --failed --max-cases 4   ← iterate
       │
       ▼
  mix test.ddls --max-cases 4            ← full re-run; confirm
```

`--max-cases 4` is mandatory on the ddls tier (PG lock contention
otherwise).

**Canonical wrapper** — the shell sandbox strips PATH; every
invocation below assumes this form:

```bash
zsh -l -c 'source ~/.zshrc && mix test.core --color 2>&1 | tee /tmp/test.txt'
```

**Never** run `mix test*` in background / async mode. Always
foreground, always piped to `tee` so the log is reviewable.

---

## Quick Diagnosis

### Step 1: Classify the failure from `mix test.core` output

After `mix ecto.reset` + `mix test.core`, read the output. Most
failures fall into one of five families:

1. Database / migration → "relation does not exist" / "column does not exist" — **Workflow 1**
2. Factory → "field is required" / "no function clause" — **Workflow 2**
3. Setup → "expected 5 arguments, got 4" — **Workflow 3**
4. Association → "cannot load/preload" — **Workflow 4**
5. Async / race (random) — **Workflow 5**

Even family 1 (DB/migration) surfaces in `test.core` first — the fix
is in the migration, but verification still starts with `test.core`.
**Do not jump straight to `test.ddls`**.

**Quick checklist before diving into a workflow:**
- [ ] Ran `mix ecto.reset` first?
- [ ] Ran `mix test.core` to see the full picture before picking a workflow?
- [ ] Reading the actual error message, not guessing?
- [ ] Fixing one file at a time (never batching)?

---

## Workflow 1: Database/Migration Issues

**Symptoms:** "relation does not exist", "column does not exist", "type does not exist"

### Step 1: Reset Database
```bash
MIX_ENV=test mix ecto.reset
```

**If reset fails:**
```bash
# Drop database manually
MIX_ENV=test mix ecto.drop --force

# Create and migrate
MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate
```

### Step 2: Verify Migrations
```bash
# Check migration status
MIX_ENV=test mix ecto.migrations

# Expected output:
# up    20241020000001  create_patients.exs
# up    20241020000002  create_appointments.exs
```

### Step 3: Test Rollback
```bash
# Ensure migrations are rollback-safe
MIX_ENV=test mix ecto.rollback --all
MIX_ENV=test mix ecto.migrate
```

**If rollback fails:**
- Check migration uses `change/0` (NOT `up/0` and `down/0`)
- Check MigrationHelper functions are rollback-safe
- Fix migration and re-test

### Step 4: Run Tests Again
```bash
zsh -l -c 'source ~/.zshrc && mix test.core --color 2>&1 | tee /tmp/test.txt'
```

If DB errors persist and the user has asked you to touch the ddls
tier (or core is green and something else is red), then:

```bash
zsh -l -c 'source ~/.zshrc && mix test.ddls --max-cases 4 --color 2>&1 | tee /tmp/test.txt'
```

---

## Workflow 2: Factory Issues

**Symptoms:** "field is required", "no function clause matching", "cannot build association"

### Step 1: Identify Failing Factory
```bash
# Run single test with stack trace
zsh -l -c 'source ~/.zshrc && mix test.core test/path/to/test.exs:42 --trace --color 2>&1 | tee /tmp/test.txt'

# Look for factory call in stack trace:
# PaymentCompliancePlatform.Factories.Healthcare.Patient.patient_factory/1
```

### Step 2: Check Factory Definition

Common factory issues:

#### Issue 1: Missing Required Fields
```elixir
# BAD - Missing required field
def patient_factory(attrs) do
  %Patient{
    status: :active
    # Missing: gender (required field)
  }
end

# GOOD - Include all required fields
def patient_factory(attrs) do
  %Patient{
    status: :active,
    gender: :male  # ← Add required field
  }
end
```

#### Issue 2: Circular Dependencies in Mapping Tables
```elixir
# BAD - Creates circular dependency
def slot_service_category_factory(attrs) do
  %SlotServiceCategory{
    slot_id: PublicHealthcareFactory.insert(:slot).id,  # Creates slot
    codeable_concept_id: PublicHealthcareFactory.insert(:codeable_concept).id
  }
  # Problem: slot_factory also creates slot_service_category → infinite loop
end

# GOOD - Require caller to provide IDs
def slot_service_category_factory(attrs) do
  %SlotServiceCategory{
    slot_id: Map.get(attrs, :slot_id),  # ← No default, caller provides
    codeable_concept_id: Map.get(attrs, :codeable_concept_id)
  }
end
```

#### Issue 3: Wrong Factory Namespace
```elixir
# BAD - Wrong namespace
test "creates patient" do
  patient = insert(:patient)  # ← Fails: no :patient factory in PaymentCompliancePlatform.Repo namespace
end

# GOOD - Namespace qualify
test "creates patient" do
  patient = PublicHealthcareFactory.insert(:patient)  # ← Correct namespace
end
```

#### Issue 4: params_for with Nested build()
```elixir
# BAD - build() doesn't serialize in params_for
params = params_for(:resource, nested: build(:nested))

# GOOD - Use Map.put for nested structures
params =
  :resource
  |> PublicHealthcareFactory.params_for(%{field: value})
  |> Map.put(:nested, %{field: value})
```

### Step 3: Fix Factory and Test
```bash
# Test factory in isolation
iex -S mix
iex> PublicHealthcareFactory.build(:patient)
# Should return struct without errors

# Run tests
zsh -l -c 'source ~/.zshrc && mix test.core test/path/to/test.exs --color 2>&1 | tee /tmp/test.txt'
```

---

## Workflow 3: Setup Issues

**Symptoms:** "expected 5 arguments, got 4", "key :datalake not found in assigns"

### Step 1: Check Setup Block

```elixir
# BAD - Missing setup
defmodule PaymentCompliancePlatform.Healthcare.PatientsTest do
  use PaymentCompliancePlatform.DataCase
  # Missing: setup :setup_healthcare_context

  test "creates patient", %{datalake: datalake} do  # ← datalake not available
    # ...
  end
end

# GOOD - Add setup
defmodule PaymentCompliancePlatform.Healthcare.PatientsTest do
  use PaymentCompliancePlatform.DataCase
  setup :setup_healthcare_context  # ← Provides datalake, user, client

  test "creates patient", %{datalake: datalake} do
    # ...
  end
end
```

### Step 2: Check Changeset Arity

```elixir
# BAD - Wrong number of arguments
def changeset(patient, datalake, attrs) do  # ← Missing user, client, batch_id
  # ...
end

# GOOD - Correct arity
def changeset(patient, %Datalake{} = datalake, %User{} = user, %DataActivationClient{} = client, batch_id, attrs) do
  # ...
end
```

### Step 3: Check Context Function Calls

```elixir
# BAD - Wrong arity
Patients.create_patient(datalake, attrs)

# GOOD - Include all required parameters
Patients.create_patient(datalake, user, client, batch_id, attrs)
```

---

## Workflow 4: Association Issues

**Symptoms:** "cannot load", "cannot preload", "association not loaded"

### Step 1: Check Preload Configuration

```elixir
# BAD - Missing preload
def list_patients(%Datalake{} = datalake) do
  repo_pid = PaymentCompliancePlatform.Datalakes.get_datalake_repo(datalake)
  with_dynamic_repo(repo_pid, HealthcareDatalakeRepo) do
    Patient
    |> HealthcareDatalakeRepo.all(prefix: datalake.db_schema)
    # Missing: |> HealthcareDatalakeRepo.preload(@patient_preloads, ...)
  end
end

# GOOD - Add preload
@patient_preloads [:marital_status, name: [], telecom: [], address: []]

def list_patients(%Datalake{} = datalake) do
  repo_pid = PaymentCompliancePlatform.Datalakes.get_datalake_repo(datalake)
  with_dynamic_repo(repo_pid, HealthcareDatalakeRepo) do
    Patient
    |> preload(^@patient_preloads)  # ← In query
    |> HealthcareDatalakeRepo.all(prefix: datalake.db_schema)
  end
end
```

### Step 2: Check Association Definition

```elixir
# BAD - Wrong association type
has_one :service_type, CodeableConcept  # ← But FHIR says 0..*

# GOOD - Correct cardinality
has_many :service_type_mappings, ServiceTypeMapping, on_delete: :delete_all
has_many :service_type, through: [:service_type_mappings, :codeable_concept]
```

### Step 3: Check Migration Foreign Keys

```bash
# Check database schema
MIX_ENV=test mix ecto.migrations

# If association missing in DB:
mix ecto.gen.migration add_missing_association --repo <RepoModule>
```

---

## Workflow 5: Async Test Issues

**Symptoms:** Random failures, "connection already started", "cannot checkout connection"

### Step 1: Check Async Configuration

```elixir
# BAD - Async with shared state
use PaymentCompliancePlatform.DataCase, async: true

test "uses datalake" do
  datalake = insert(:datalake)  # ← May conflict with other async tests
end

# GOOD - Use async: false for tests with shared state
use PaymentCompliancePlatform.DataCase, async: false  # ← Safer for datalake tests
```

### Step 2: Use Proper Isolation

```elixir
# Each test should create its own data
setup do
  org = insert(:org)
  datalake = insert(:datalake, org: org)
  {:ok, datalake: datalake}
end

test "isolated test", %{datalake: datalake} do
  patient = PublicHealthcareFactory.insert(:patient)  # ← Test-specific data
  # ...
end
```

---

## Systematic Fix Process (One File at a Time)

### Step 1: Capture Failed Files
```bash
# Discover failures — run core, log to file
zsh -l -c 'source ~/.zshrc && mix test.core --color 2>&1 | tee /tmp/test.txt'

# Extract failed file paths
grep "(test)" /tmp/test.txt | cut -d":" -f 1 | sort | uniq > platform_failed_files.txt
cat platform_failed_files.txt
```

### Step 2: Fix One File at a Time
```bash
FILE=$(head -n 1 platform_failed_files.txt)

# Iterate on the one file (re-runs only what's red)
zsh -l -c 'source ~/.zshrc && mix test.core $FILE --failed --color 2>&1 | tee /tmp/test.txt'

# Full file re-run once you think it's green
zsh -l -c 'source ~/.zshrc && mix test.core $FILE --color 2>&1 | tee /tmp/test.txt'

# Move to next file only when this one is fully green
```

**Never use `--max-failures`** — always `--failed`. `--failed` re-runs
only what was red last time; `--max-failures` stops early and hides
the real picture.

### Step 3: Verify — `--failed` green, then full re-run
```bash
# When mix test.core --failed shows zero failures, run the FULL core
# tier one more time to catch anything the fixes broke elsewhere.
zsh -l -c 'source ~/.zshrc && mix test.core --color 2>&1 | tee /tmp/test.txt'

# If test.ddls was also failing, same loop:
#   zsh -l -c 'source ~/.zshrc && mix test.ddls --failed --max-cases 4 --color 2>&1 | tee /tmp/test.txt'
#   then:
#   zsh -l -c 'source ~/.zshrc && mix test.ddls --max-cases 4 --color 2>&1 | tee /tmp/test.txt'

# Coverage (core tier)
zsh -l -c 'source ~/.zshrc && mix test.core --cover --color 2>&1 | tee /tmp/test.txt'
# Or browsable HTML report:
zsh -l -c 'source ~/.zshrc && mix coveralls.html'

# Compile clean
zsh -l -c 'source ~/.zshrc && MIX_ENV=test mix compile --warnings-as-errors'
```

---

## Common Test Patterns and Fixes

### Pattern 1: Test Setup
```elixir
# BEFORE:
test "creates resource" do
  datalake = insert(:datalake)
  attrs = %{status: :active}
  Context.create_resource(datalake, attrs)  # ← Wrong arity
end

# AFTER:
setup :setup_healthcare_context

test "creates resource", %{datalake: datalake, user: user, client: client} do
  attrs = %{status: :active}
  Context.create_resource(datalake, user, client, nil, attrs)  # ← Correct
end
```

### Pattern 2: Factory Usage
```elixir
# BEFORE:
patient = insert(:patient)  # ← Wrong namespace

# AFTER:
patient = PublicHealthcareFactory.insert(:patient)  # ← Correct namespace
```

### Pattern 3: Nested Associations
```elixir
# BEFORE (params_for with build):
params = params_for(:appointment, participants: [build(:participant)])

# AFTER (Map.put):
params =
  :appointment
  |> PublicHealthcareFactory.params_for()
  |> Map.put(:participants, [%{practitioner_id: practitioner.id}])
```

### Pattern 4: TokenizedData
```elixir
# BEFORE:
attrs = %{birth_date: ~D[1990-01-15]}  # ← Wrong type

# AFTER:
attrs = %{birth_date: %{type: :date, value: ~D[1990-01-15]}}  # ← Correct
```

---

## Debugging Tools

### IEx for Interactive Testing
```bash
# Start IEx with test environment
MIX_ENV=test iex -S mix

# Load test helpers
iex> Code.require_file("test/support/data_case.ex")
iex> import PaymentCompliancePlatform.DataCase

# Test factory
iex> PublicHealthcareFactory.build(:patient)

# Test context function
iex> org = insert(:org)
iex> datalake = insert(:datalake, org: org)
iex> PaymentCompliancePlatform.Healthcare.Patients.list_patients(datalake)
```

### ExUnit Tracing
```bash
# Run with trace for detailed output
zsh -l -c 'source ~/.zshrc && mix test.core test/path/to/test.exs --trace --color 2>&1 | tee /tmp/test.txt'

# Run with seed for reproducible random failures
zsh -l -c 'source ~/.zshrc && mix test.core --seed 123456 --color 2>&1 | tee /tmp/test.txt'
```

### Compiler Warnings
```bash
# Check for warnings
MIX_ENV=test mix compile

# Treat warnings as errors
MIX_ENV=test mix compile --warnings-as-errors
```

---

## Prevention Checklist

Before committing code:

- [ ] Core tier green: `mix test.core` (after `mix test.core --failed` shows no failures)
- [ ] DDL tier green (only if it was in scope): `mix test.ddls --max-cases 4`
- [ ] No compiler warnings: `MIX_ENV=test mix compile --warnings-as-errors`
- [ ] Factories work in isolation
- [ ] Setup blocks provide all needed assigns
- [ ] Context functions have correct arity
- [ ] Migrations are rollback-safe
- [ ] Coverage maintained: `mix test.core --cover` (or `mix coveralls.html` for browsable)

---

## Next Steps

- For mechanical multi-file refactors: use [/dev:create-ast-refactor-task](../dev/create-ast-refactor-task.md)
- For lifting module coverage to 100%: use [/qa:increase-test-coverage](./increase-test-coverage.md)
- For adding resources: use the per-domain dataset skills under `/dev:*`
