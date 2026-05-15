---
name: quality-checks
description: Run all code quality checks before committing
when_to_use:
  - Before creating a pull request
  - After making significant changes
  - Pre-commit verification (REQUIRED)
related_commands:
  - /qa:fix-failing-tests (Step 5 / Step 6 failures)
  - /qa:increase-test-coverage (Step 6 coverage gaps)
  - /qa:check-api-quality (structural drift checker for controllers)
  - /qa:review (multi-agent review after all gates pass)
---

# Run Quality Checks Before Committing

Run all quality checks that must pass before committing code. Mirrors the
pre-commit checklist in [CLAUDE.md](../../../CLAUDE.md).

## Usage

```
/qa:quality-checks
```

The mix alias `mix quality` runs format-check + sobelow + credo as one
command; this skill walks through every gate including tests and coverage.

---

## Critical Gate Rule

**Each step is a hard gate. If a step fails, STOP — do NOT proceed to the next step.**

1. Collect ALL failing files/issues from the failing step.
2. Fix **one issue at a time** using the appropriate skill
   ([/qa:fix-failing-tests](./fix-failing-tests.md) for test failures,
   [/qa:increase-test-coverage](./increase-test-coverage.md) for coverage,
   [/qa:check-api-quality](./check-api-quality.md) for controller drift).
3. Re-run the **same step** to confirm it passes.
4. Only then move to the next step.

No skipping ahead. No fixing-while-running.

---

## Code Change Permission Rule

When credo, sobelow, or a compiler warning flags an issue in `lib/`, do
**NOT** fix it autonomously:

1. Show the user the exact issue (file, line, message).
2. Present the available options (e.g. ignore vs refactor vs `@doc false`).
3. Wait for the user to choose.
4. Only then apply the chosen fix.

This avoids silently changing semantics in places the user wants to review.

---

## Step 1: Compile clean (no warnings)

```bash
mix compile --warnings-as-errors
```

Any warning is a failure. Fix it before continuing — don't `--force` past it.

---

## Step 2: Format check

```bash
mix format --check-formatted
```

If anything is out, the failing files are listed. Run `mix format` (without
`--check-formatted`) to apply, review the diff, then re-run the check.

---

## Step 3: Static security (sobelow)

```bash
mix sobelow --config
```

Reads `.sobelow-conf` if present. Any high-confidence finding is a fail;
medium/low can be discussed with the user (see Code Change Permission Rule).

---

## Step 4: Credo (strict)

```bash
mix credo --strict
```

`--strict` is the gate — readability issues, refactor suggestions, and
warnings all count. Use `/qa:fix-failing-tests` only for **test** failures;
for credo issues, surface the option set to the user first.

The `mix quality` alias chains the format-check + sobelow + credo step:

```bash
mix quality
```

Equivalent to running steps 2, 3, 4 back-to-back. Useful as a single pre-commit
invocation once you're confident none of the steps will fail.

---

## Step 5: Test suite

```bash
mix test
```

Must be 0 failures. If any test fails, switch to
[/qa:fix-failing-tests](./fix-failing-tests.md) — that skill runs the
`mix test --failed` iteration loop until the failed-list drains.

Per [CLAUDE.md § Testing Standards](../../../CLAUDE.md): **NO mocks/stubs —
use real implementations**. Don't introduce mocks to make a test pass. The
two shared real dependencies in tests are:

- `moov/watchman:v0.61.1` container (OFAC SDN screening) —
  `make run-backing-services` brings it up
- `AtomicFi.DecisionContext.BlocklistCache` ETS table (per-tenant warmup) —
  call `BlocklistCache.refresh_tenant_cache(tenant.id)` in setup if needed

Tests that touch either are typically `async: false`. Don't flip them to
`async: true` to "speed things up" — they race against shared state.

---

## Step 6: Coverage

```bash
mix coveralls 2>&1 | tail -20
```

Look at the `[TOTAL]` line. Per [coveralls.json](../../../coveralls.json),
the minimum coverage target is **95%**. Files in `skip_files` (`test/`,
`lib/mix/tasks/`, `lib/atomic_fi_web/components/core_components.ex`) are
excluded — that's intentional, those are dev tooling / generated scaffold,
not production code.

If `[TOTAL]` is below 95% or below the pre-change baseline, switch to
[/qa:increase-test-coverage](./increase-test-coverage.md) on the worst-offending
module.

To generate the HTML report (helpful for visualising which lines are
uncovered):

```bash
mix coveralls.html
open cover/excoveralls.html
```

---

## Step 7: Structural checks (atomic-fi-specific)

These cover invariants documented in [CLAUDE.md](../../../CLAUDE.md) that
don't fit into compile/credo/sobelow gates.

### Step 7a: No PATCH routes

Per project convention, updates use `PUT` (full resource replacement) — never
`PATCH`:

```bash
grep -nE '^\s*patch\s+"' lib/atomic_fi_api/routes.ex
grep -nE 'resources.*:update' lib/atomic_fi_api/routes.ex
```

Both must return zero hits. `resources ..., only: [:create, :show, :update, ...]`
generates BOTH `PUT` and `PATCH` — drop `:update` from `only:` and add an
explicit `put "/<path>/:id"` route.

### Step 7b: No `Map.from_struct` / `Mapper.to_map` in controllers

Per [CLAUDE.md § Controller / Context Contract](../../../CLAUDE.md),
controllers pass typed request structs directly to contexts.
`ExOpenApiUtils.Changeset.cast/3` (called inside `changeset/2`) handles the
struct-to-map conversion internally:

```bash
grep -rnE "Map\.from_struct|Mapper\.to_map" lib/atomic_fi_api/controllers/
```

Zero hits required. Any hit is a contract violation — see
[/qa:check-api-quality](./check-api-quality.md) for the full controller audit.

### Step 7c: Context functions use `def_with_rls_and_logging`

Public context functions that perform RLS-scoped DB operations should use
the macro so RLS + audit-log emission stay consistent:

```bash
grep -rn "def " lib/atomic_fi/<context>/<context>.ex \
  | grep -v "defp\|def_with_rls_and_logging"
# Any `def <name>(session, ...)` not wrapped is suspicious
```

This is a heuristic — some context functions legitimately don't take a
session (e.g. seed helpers, validation-only functions). Treat hits as a
review prompt, not a hard fail.

---

## Step 8: Pre-commit summary

After every step has passed:

```
  Format:        PASS (mix format --check-formatted)
  Security:      PASS (mix sobelow --config)
  Credo:         PASS (mix credo --strict)
  Compile:       PASS (mix compile --warnings-as-errors)
  Tests:         PASS (mix test — 790+ tests, 0 failures)
  Coverage:      PASS (mix coveralls — [TOTAL] ≥ baseline, target 95%)
  Routes:        PASS (no PATCH, no resources:update)
  Contract:      PASS (no Map.from_struct / Mapper.to_map in controllers)
```

Only when all eight read PASS, commit with:

```bash
git commit -S -m "<conventional commit msg>"
```

The `-S` flag is mandatory (GPG-signed) per the user's global Claude config
and project `CLAUDE.md`. No `--no-verify`, no skipping hooks.

---

## Common failure modes

### Coverage dropped vs baseline

Likely cause: you removed a test, refactored without porting its coverage,
or added new code without tests. Run the offending module through
[/qa:increase-test-coverage](./increase-test-coverage.md) before continuing.

### `mix sobelow` flags `Config.HTTPS` or `Config.HSTS`

Common in dev — atomic-fi is HTTP-only for local. The findings are
typically `:low` confidence; check `.sobelow-conf` or the user's
preferences before suppressing.

### Credo `Readability.ModuleDoc`

Add `@moduledoc` (or `@moduledoc false` for tiny private modules). For
auto-generated OpenApiSpex schema modules, `@moduledoc false` is the right
call — they're machine-managed.

### `mix test` hangs on a screening test

Watchman container is down or unreachable. Verify:

```bash
curl -s http://localhost:8084/ping   # expected: PONG
make run-backing-services            # bring it up via docker compose
```

If watchman is up and the test still hangs, suspect a `Req.Test.stub` or
`Req.Test.set_req_test_to_private` not being cleaned up — check test
teardown.

---

## Related Commands

- [/qa:fix-failing-tests](./fix-failing-tests.md) — iterate on failing tests with `mix test --failed`
- [/qa:increase-test-coverage](./increase-test-coverage.md) — push a module toward 100% coverage
- [/qa:check-api-quality](./check-api-quality.md) — structural drift checker for controllers
- [/qa:review](./review.md) — multi-agent code review for pre-PR
- [/dev:create-rest-api](../dev/create-rest-api.md) — the maker side; check its output here before commit
