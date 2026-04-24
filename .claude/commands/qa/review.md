---
name: review
description: Smart multi-agent code review that selects and runs the right reviewers in parallel based on file types and context
when_to_use:
  - Reviewing code before creating a PR
  - Getting expert feedback on new or modified code
  - Post-implementation review of features
related_guides:
  - guides/cheatsheet/quality_gates.cheatmd
  - guides/cheatsheet/debugging.cheatmd
related_commands:
  - /qa:quality-checks (run mix format + credo --strict + sobelow locally before review)
  - /qa:fix-failing-tests (fix findings from the Test Analyzer)
  - /qa:check-api-quality (controller-specific audit to run alongside a review)
---

# Smart Multi-Agent Code Review

Intelligent code review that analyzes the input, selects the right expert reviewers, and runs them in parallel.

## Inputs

You will receive some or all of the following. Work with whatever is provided:

- **file** — path(s) to file(s) to review
- **description** — what the code does or what changed
- **diff** — a git diff or inline diff of changes
- **pr** — a PR number or GitHub PR link

If only a PR link/number is provided, fetch the diff and changed files using `gh pr diff <number>` and `gh pr view <number> --json files`.

If nothing is provided, use `git diff` (unstaged) + `git diff --cached` (staged) to gather the current working changes.

## Arguments

$ARGUMENTS

## Instructions

### Step 1: Gather Context

Collect the review material:

1. If a **PR link/number** was given:
   ```bash
   gh pr diff <number>
   gh pr view <number> --json title,body,files
   ```

2. If **file paths** were given, read each file.

3. If **neither** was given, gather current changes:
   ```bash
   git diff
   git diff --cached
   git diff --name-only HEAD
   ```

4. Identify all changed/target files and their extensions/types.

### Step 2: Classify Files and Select Reviewers

Based on the files being reviewed, select ALL applicable reviewers from the table below. **Always run multiple reviewers** — the goal is comprehensive coverage from different expert perspectives.

#### Naming Convention

**IMPORTANT:** When referencing reviewers in output (reports, PR comments, logs), use **technology-based names** (e.g., "Elixir Reviewer", "LiveView Reviewer"), NOT real person names. The agent filenames use person names internally for routing, but all user-facing output must use the display names from the table below. This avoids implying endorsement or affiliation.

#### Reviewer Selection Matrix

| File Pattern / Content | Display Name | Agent Type | Agent Path |
|---|---|---|---|
| `.ex`, `.exs` (non-LiveView) — Elixir contexts, schemas, workers, migrations | **Elixir Reviewer** | `jose-valim-code-reviewer` | `.claude/agents/reviewer/review-agent.md` |
| `_live.ex`, `_component.ex`, `.heex` — LiveView modules, components, templates | **LiveView Reviewer** | `chris-mccord-code-reviewer` | `.claude/agents/reviewer/liveview-reviewer.md` |
| **ALWAYS** — runs on every review unconditionally | **Silent Failure Hunter** | `pr-review-toolkit:silent-failure-hunter` | _(built-in)_ |
| **ALWAYS** — runs on every review to check impact on existing tests, missing coverage, why tests are absent | **Test Analyzer** | `pr-review-toolkit:pr-test-analyzer` | _(built-in)_ |
| `.ts`, `.tsx`, `.js`, `.jsx` with React imports | **React Reviewer** | `dan-abramov-code-reviewer` | `.claude/agents/reviewer/dan-abramov-code-reviewer.md` |
| `.ts`, `.tsx` with Remix/React Router imports, loaders, actions | **Remix/Router Reviewer** | `rf-mj-code-reviewer` | `.claude/agents/reviewer/rf-mj-code-reviewer.md` |
| Any `.ts`, `.tsx`, `.js`, `.jsx` file — ALWAYS when TypeScript/JavaScript is present | **TypeScript Reviewer** | `anders-code-reviewer` | `.claude/agents/reviewer/anders-hejlsberg-code-reviewer.md` |
| `.vue`, `.ts` with Vue/Vite imports, composables (`use*`) | **Vue Reviewer** | `evan-you-code-reviewer` | `.claude/agents/reviewer/evan-you-code-reviewer.md` |
| `.test.ts`, `.spec.ts`, Vitest patterns, `describe`/`it` | **Vitest Reviewer** | `antfu-code-reviewer` | `.claude/agents/reviewer/antfu-code-reviewer.md` |
| `.astro`, minimal-JS architecture, Islands pattern | **Astro Reviewer** | `fks-code-reviewer` | `.claude/agents/reviewer/fks-code-reviewer.md` |
| `.html`, `.heex`, Tailwind classes, utility-first CSS, component markup | **Tailwind Reviewer** | `adam-wathan-code-reviewer` | `.claude/agents/reviewer/adam-wathan-code-reviewer.md` |

#### Selection Rules

**Always-on reviewers (every single review):**
1. **Silent Failure Hunter** — ALWAYS runs. Checks error handling, catch blocks, fallback logic, swallowed errors.
2. **Test Analyzer** — ALWAYS runs. Checks impact on existing tests, missing test coverage, why tests are absent for new code, whether changes break existing test assumptions.

**Language/framework reviewers (based on file types):**
3. **Elixir code** (.ex/.exs): ALWAYS include Elixir Reviewer.
4. **LiveView code** (.heex, `_live.ex`, `_component.ex`): ALWAYS include BOTH Elixir Reviewer AND LiveView Reviewer.
5. **LiveView with Tailwind**: Include Elixir Reviewer + LiveView Reviewer + Tailwind Reviewer.
6. **TypeScript/JavaScript** (.ts/.tsx/.js/.jsx): ALWAYS include TypeScript Reviewer for type design review.
7. **React code**: Include React Reviewer. If using Remix/React Router, ALSO include Remix/Router Reviewer.
8. **Vue code**: Include Vue Reviewer. If using Vitest, ALSO include Vitest Reviewer.
9. **Frontend markup with Tailwind**: Include Tailwind Reviewer alongside the framework reviewer.
10. **Astro/Islands**: Include Astro Reviewer.
11. **Minimum 3 reviewers** — always run at least: Silent Failure Hunter + Test Analyzer + primary domain expert.

### Step 3: Launch Reviewers in Parallel

Use the `Agent` tool (aka `Task` in some Claude Code docs) to launch ALL selected reviewers simultaneously. Each reviewer gets the same context.

Use the `subagent_type` from the Reviewer Selection Matrix to launch each agent. Both built-in and project agents are registered as named agent types.

> **Plugin dependency:** `pr-review-toolkit:silent-failure-hunter` and `pr-review-toolkit:pr-test-analyzer` require the `pr-review-toolkit` Claude Code plugin. If it is not installed in this environment, skip those two always-on slots and note the gap in the synthesized report — do not fail the whole review.

Each reviewer's prompt should include:
- The file contents or diff
- The description of what changed
- Instruction to follow their specific review methodology
- Instruction to output their structured review format

**CRITICAL: Launch all reviewers in a SINGLE message with multiple `Agent` tool calls so they run in parallel.**

Example parallel launch pattern:
```
Agent 1: Elixir Reviewer reviewing contexts and schemas
Agent 2: LiveView Reviewer reviewing LiveView modules
Agent 3: Silent Failure Hunter checking error handling (if plugin available)
Agent 4: Test Analyzer checking test coverage (if plugin available)
```

### Step 4: Synthesize Results

After all reviewers complete, compile a unified review report:

```markdown
# Code Review Report

## Reviewers Engaged
- [List each reviewer and why they were selected]

## Critical Issues (must fix)
[Deduplicated critical issues from all reviewers, attributed to reviewer]

## Improvements Recommended
[Merged improvement suggestions, grouped by theme]

## What Works Well
[Positive feedback from reviewers]

## Summary
[Overall verdict — is this code ready to merge?]
```

**Deduplication rules:**
- If multiple reviewers flag the same issue, consolidate and note agreement
- Prioritize: security > correctness > performance > maintainability > style
- Conflicting opinions: present both perspectives and recommend the safer path

**Test file vs lib file distinction — MANDATORY:**

Before surfacing any finding, classify the file:
- `test/**/*_test.exs` or `test/support/**/*.ex` → **test code**
- `lib/**/*.ex` → **production code**

Apply different standards:

| Concern | `lib/` (production) | `test/` (test code) |
|---|---|---|
| Readability style | strict — idiomatic, composable | relaxed — explicit and dumb is correct; verbose sequential code is fine |
| Helper extraction | required when duplication risks drift | optional; repetition in tests is often intentional for readability |
| Pattern matching depth | enforce | suggest only if the test is genuinely unreadable |
| Error message quality | strict | n/a — tests assert, they don't format user messages |
| Defensive guards | enforce | skip — test setup is not production boundary code |
| Observability / logging | enforce | n/a |
| API ergonomics | enforce | n/a |

**Never flag in test files:**
- "this could be extracted to a helper" (unless the same block appears 4+ times across multiple files)
- "use pattern matching instead of if/else"
- "this assertion message is opaque" (ExUnit already shows the diff)
- "add structured logging"
- Positional index access on fixture lists (it's intentional fixture anchoring)
- Defensive guards around Ecto/Oban contracts that already guarantee the invariant

### Step 5: Present Report

Output the unified report to the user. If critical issues were found, clearly state the code is NOT ready to merge until they are addressed.
