---
name: feature-walkthrough
description: Human-led browser session that produces or extends an ExDoc how-to guide with screenshots/MP4s, creates or edits Playwright E2E specs, and files GitHub sub-issues for blockers
when_to_use:
  - Documenting a platform capability end-to-end with screenshots and MP4 recordings for the ExDoc site
  - QA walkthrough that produces user-facing how-to guides in guides/howtos/
  - Creating or editing Playwright E2E specs (playwright-e2e/tests/) alongside the guide
  - Filing tracked GitHub sub-issues when something is broken during the walkthrough
related_guides:
  - guides/howtos/README.md
  - guides/core-infra/datalakes.md
related_commands:
  - /qa:playwright-e2e-spec (write a new independent E2E spec)
  - /qa:pair-qa (pre-release QA pass across the full E2E suite)
  - /ui:playwright-pair-program (manual QA / PR review with action recording; also holds the shared webm→mp4 concat recipe)
---

# Capability Walkthrough — How-To Guide + E2E Spec Generator

Collaborative session where human leads and Claude follows instructions using **Playwright MCP**.
Three co-deliverables are produced from each session:

1. **How-to guide** — `guides/howtos/howto_<capability>.md` with inline screenshots and MP4 recordings,
   fully compatible with `mix docs` (ExDoc). Guides document **platform capabilities** (how to
   manage datalakes, how to use data, how to manage workflows) — not individual features. Each
   session either creates a new how-to guide or extends an existing one with new sections.
2. **E2E spec** — `playwright-e2e/tests/<capability>.spec.ts` (kebab-only filename, no numeric
   prefix — run order lives in `package.json` scripts and `playwright.config.ts`) that validates
   the same flows, with `videoGap()` pauses so the auto-recorded MP4 is watchable
3. **GitHub sub-issues** — filed for any blocker discovered during the walkthrough

When stuck, Claude asks whether to fix now or file a GitHub sub-issue — never skips silently.

## Usage

```
/ui:feature-walkthrough [capability-name or context.md]
```

**Arguments:**
- `$ARGUMENTS` — Capability name (e.g. `manage-datalakes`, `manage-workflows`, `use-data`) or
  path to a context markdown file. Should map to a `howtos/howto_<name>.md` guide.

---

## Default POV: Tenant Admin

Unless the user specifies otherwise, all walkthroughs are from the perspective of a **tenant admin**
(Sarah). Both manual sessions and E2E specs use the same user:

- **Sign in as Sarah** — `sarah@e2e.local` / `devpassword123`. This is the tenant admin user
  for all walkthrough and E2E scenarios.
- **After a DB reset**, Sarah won't exist. Bootstrap her first (see Phase 2): sign in as
  platform admin (`admin@dev.local` / `devpassword`), create the org/tenant/datalake, then
  invite or create Sarah as a tenant admin member. Once Sarah exists, switch to her for the
  rest of the walkthrough.
- **E2E specs** read Sarah's credentials from state (`loadState().sarahEmail` / `sarahPassword`).
  Sarah is created by the `sign-up`, `tenant-setup`, `datalake-setup` specs.
- After sign-in, switch to the target tenant before starting the walkthrough
- Navigation uses sidebar menu items visible to the tenant admin role
- Document routes as `/app/...` paths (tenant-scoped, not platform-admin `/admin/...` paths)
- **Guide content is generic** — write "navigate to Data Lakes" not "sign in as Sarah." The
  guide is for any tenant admin, not a specific test user.

If the capability requires a different role (platform admin, team member, viewer), the human will
say so at the start. Adjust authentication and note the role in the guide's Prerequisites.

---

## CRITICAL RULES FOR CLAUDE

### Rule 0: The Guide and E2E Spec Are Co-Deliverables

`guides/howtos/howto_<capability>.md` is the permanent documentation. `playwright-e2e/tests/<capability>.spec.ts`
is the automated validation. Write to the guide after every documented step. Update or scaffold the
E2E spec when the human requests it (typically after completing a logical section or at wrap-up).

### Playwright Behavior (MANDATORY)

1. **WAIT for explicit instructions** before every action
2. **NEVER fill forms** unless told: "fill the name field with X"
3. **NEVER click buttons** unless told: "click the Save button"
4. **NEVER navigate** unless told: "go to /app/datalakes"
5. **Take a screenshot** after each step worth documenting
6. **Ask clarifying questions** if instructions are unclear
7. **ALWAYS open `playwright-cli` with `--headed`** — the CLI defaults to
   headless (opposite of the node library). A session without `--headed` is
   invisible to the human; the walkthrough is collaborative and requires a
   visible browser. Save screenshots to `.playwright-cli/<ISSUE>-screenshots/`
   (gitignored via `.playwright-cli/` in `.gitignore`) so they're available
   to copy into `guides/images/...` later.

   ```bash
   # CORRECT
   npx playwright-cli -s=<session> open --browser=chrome --headed <url>

   # WRONG — invisible browser
   npx playwright-cli -s=<session> open <url>
   ```

### When Stuck — Always Ask First

When something is broken, unexpected, or unclear — **stop and ask**:

```
We're stuck at step [N]: <what happened>

What would you like to do?
A) Fix it now — describe the fix, or say "investigate" and I'll check server logs and DB state
B) File a GitHub issue — I'll create a sub-issue with screenshots and reproduction steps, then continue
```

Never autonomously fix or skip a broken step.

---

## How-To Guide Conventions

Guides follow the `howtos/howto_<capability>.md` naming convention and document **platform capabilities**
from the tenant admin's perspective. Each guide covers a broad capability area — not a single feature.

| Existing guide | Capability area |
|---|---|
| `howtos/howto_manage_tenants.md` | Tenant creation, invitations, member management |
| `howtos/howto_manage_datalakes.md` | Datalake provisioning, migration, dataset browsing |
| `howtos/howto_manage_data_activation.md` | Data sources, ingestion, sync |
| `howtos/howto_manage_workflows.md` | Connected apps, tools, agentic workflows, action status updaters |
| `howtos/howto_use_data.md` | Querying, browsing, and exporting data |

When starting a walkthrough:
- **Prefer extending an existing how-to guide** with new sections rather than creating a new guide.
  Most capabilities fit within the guides above.
- **Create a new guide** only when the capability area is genuinely distinct (e.g. `howtos/howto_manage_access_control.md`).
- Guide sections are numbered (`## 1.`, `## 2.`) and each section covers a complete task a tenant
  admin can accomplish (e.g. "Create a Data Lake", "Configure Cloud Storage", "Deploy a Tool").

---

## Phase 1: Initialization

### Step 1.1: Parse Arguments

- `$ARGUMENTS` is a markdown file → read it for context; derive capability name from filename
- `$ARGUMENTS` is a short name (e.g. `manage-datalakes`) → use as-is
- No argument → ask: "What platform capability are we documenting today?"

Check existing how-to guides first:

```bash
ls guides/howtos/howto_*.md
```

If an existing guide covers this capability area, default to extending it.

Derived values:
- `CAPABILITY_NAME` — kebab-case slug (e.g. `manage-datalakes`)
- `GUIDE_PATH` — `guides/howtos/howto_<CAPABILITY_NAME>.md` (existing or new)
- `SCREENSHOT_DIR` — `guides/assets/screenshots/<CAPABILITY_NAME>/` (or `guides/images/<dirname>/` if existing guide already uses that)
- `RECORDING_DIR` — `guides/assets/recordings/<CAPABILITY_NAME>/`

### Step 1.2: Ensure ExDoc Assets Are Configured

Check `mix.exs` for the ExDoc `:assets` key:

```bash
grep "assets:" mix.exs
```

If missing, add it to the `docs:` section in `mix.exs`:

```elixir
# Before (in the docs: fn -> [...] block):
extras: [...]

# After:
extras: [...],
assets: %{"guides/assets" => "assets"}
```

This tells ExDoc to copy `guides/assets/` into the generated doc output so that
`![alt](assets/screenshots/...)` paths resolve correctly in `mix docs` HTML.

### Step 1.3: Create Asset Directories

Use the same directory structure that the existing guide uses, or create new ones:

```bash
# If the existing guide already uses guides/images/<dirname>/ — use that
# Otherwise, use the standard structure:
mkdir -p guides/assets/screenshots/<CAPABILITY_NAME>
mkdir -p guides/assets/recordings/<CAPABILITY_NAME>
```

Add `.gitkeep` if empty, but assets will be committed alongside the guide.

### Step 1.4: Create or Resume Guide

**Prefer extending an existing guide.** Read `GUIDE_PATH` and check its current state:

- Guide exists and covers this capability area → read it, identify the last section number,
  and ask: "This guide has sections 1–N. Which section should I extend, or should I add new
  sections after §N?"
- Guide exists but is a stub or early draft → ask: "Resume this guide from §<last>?"
- No matching guide exists → create a new one:

```markdown
# How to <Capability Description>

<!-- MDOC !-->

How-to guide for <capability area>: <list the sub-topics covered>.

**Menu source:** `PlatformWeb.Menus.SidebarTenant` (`:group_name`)

## Prerequisites

- App running at `http://localhost:4000`
- <other prerequisites, link to dependency guides>

---
```

Register it in `mix.exs` `extras:` list under the **"How-Tos"** group (matches the 8-group ExDoc IA). Example:

```elixir
# In extras:
"guides/howtos/howto_<capability>.md",

# In groups_for_extras (already present — just drop the new guide into the matching regex):
"How-Tos": ~r|guides/howtos/|,
```

### Step 1.5: Identify or Create E2E Spec

Check existing specs:

```bash
ls playwright-e2e/tests/*.spec.ts
```

- If a spec already exists for this capability → read it and ask: "Update this spec or create a new one?"
- Otherwise: `SPEC_PATH` is `playwright-e2e/tests/<CAPABILITY_NAME>.spec.ts` (kebab-only, no numeric prefix).

**Naming convention:** spec filenames are pure kebab-case. Run order lives in `package.json`
scripts (`test:<capability>`) and `playwright.config.ts` projects — never in filenames.

Don't write the spec yet — scaffold it after the first few walkthrough sections give enough
context for the test structure.

### Step 1.6: Get Release / Milestone Context

```bash
git branch --show-current

# Find milestones (for issue linking)
gh api /repos/{owner}/{repo}/milestones --jq '.[] | "\(.number) \(.title)"'
```

Store the milestone number if one matches the current branch name or release.

### Step 1.7: Start Browser

```typescript
await browser_navigate({ url: "http://localhost:4000" });
await browser_snapshot();
```

---

## Phase 2: Authentication & Environment Setup

Sign in as Sarah (`sarah@e2e.local` / `devpassword123`):

1. Navigate to `/auth/sign-in`
2. Fill email `sarah@e2e.local`, password `devpassword123`
3. Click "Sign in" → wait for `/app*`
4. Switch to the target tenant if needed

Don't document the login in the guide unless login IS the capability being documented.

### After a DB Reset — Create Sarah & Bootstrap Environment

If the database was recently reset (`mix ecto.reset`), Sarah won't exist and there are no
tenants or datalakes. Bootstrap the minimum environment before the walkthrough:

1. **Sign in as platform admin** — `admin@dev.local` / `devpassword` (the only user after reset)
2. **Create an org** (if none exists) — navigate to org setup
3. **Create a tenant** — follow the flow in `howtos/howto_manage_tenants.md`:
   - Navigate to **Admin Settings → Tenants → + New Tenant**
   - Fill name, slug, industry
4. **Create Sarah as tenant admin** — invite or create `sarah@e2e.local` with the `admin` role
   on the new tenant
5. **Create a datalake** — follow the flow in `howtos/howto_manage_datalakes.md`:
   - Switch to the new tenant
   - Navigate to **Tenant Configuration → Data Lakes → + New Data Lake**
   - Configure database connections and cloud storage
   - Run migrations until status is "Ready"
6. **Sign out of platform admin, sign in as Sarah** — use `sarah@e2e.local` / `devpassword123`
   for the rest of the walkthrough
7. **Switch to the tenant** — use the tenant switcher dropdown

Ask the human: "DB looks fresh — should I walk through Sarah + tenant + datalake setup first,
or skip ahead (you'll set it up)?"

This setup phase is NOT documented in the current guide unless the guide IS about tenant/datalake
management (see [howtos/howto_manage_tenants.md](../../../guides/howtos/howto_manage_tenants.md),
[howtos/howto_manage_datalakes.md](../../../guides/howtos/howto_manage_datalakes.md)). It's just a
prerequisite bootstrap.

---

## Phase 3: The Walkthrough Session

**Human leads. Claude documents.**

### For Each Step the Human Requests

1. Execute the action via Playwright MCP
2. Take a screenshot immediately after:
   ```
   browser_take_screenshot({
     filename: "guides/assets/screenshots/<CAPABILITY_NAME>/<N>-<slug>.png"
   })
   ```
3. Append the guide section (see format below)
4. Report what happened

### Guide Section Format

```markdown
---

## <N>. <Section Title>

<video of the walkthrough section — omit if no recording available>

**Route:** `/app/path/here`

<One or two sentences: what this step does and why it matters.>

### Steps

1. Navigate to **[Section]** → **[Subsection]** in the sidebar
2. Click **[Button or Link]**
3. Fill in the required fields:
   - **Field Name:** example value
4. Click **Save** (or **Submit**)

![<Descriptive alt text for the screenshot>](assets/screenshots/<CAPABILITY_NAME>/<N>-<slug>.png)

> **Note:** <optional tip, warning, or constraint — omit if not needed>

### API Calls

```http
POST /api/v1/resource
Status: 201 Created
```

### Status

PASSED
```

**Status values:**
- `PASSED`
- `WORKAROUND` — describe it
- `BUG — [#issue-number](url)` — link to filed issue
- `BLOCKED — [#issue-number](url)` — can't proceed without fix

### Screenshot Naming Convention

```
<N>-<slug>.png

Examples:
01-datalake-list.png
02-create-datalake-form.png
03-datalake-created-flash.png
```

Use zero-padded numbers so they sort correctly in the filesystem.

### MP4 Recording Convention

Playwright auto-records MP4s when `video: "on"` is set in `playwright.config.ts`.
After running the E2E spec, collect the recording from `playwright-e2e/test-results/`:

```bash
# Find the recording for a specific test
find playwright-e2e/test-results -name "*.webm" -path "*<capability>*"

# Copy to guide assets (convert if needed)
cp playwright-e2e/test-results/<path>/video.webm guides/assets/recordings/<CAPABILITY_NAME>/<N>-<slug>.webm
```

For production guides, upload recordings to Cloudflare Stream and embed as iframe:

```markdown
<iframe src="https://customer-gd12bzv95j5nkvu7.cloudflarestream.com/<VIDEO_ID>/iframe"
  allow="autoplay; encrypted-media" allowfullscreen
  style="width:100%; max-width:800px; aspect-ratio:16/9; border:0; border-radius:8px; margin:1rem 0;">
</iframe>
```

For local/draft guides, reference the local file:

```markdown
<video controls style="width:100%; max-width:800px; border-radius:8px; margin:1rem 0;">
  <source src="assets/recordings/<CAPABILITY_NAME>/<N>-<slug>.webm" type="video/webm">
</video>
```

---

## Phase 4: E2E Spec Management

The human may ask to create or edit E2E specs at any point during the walkthrough. This can happen:
- After completing a logical section ("let's write the E2E for that")
- When a flow is complex and needs automated regression coverage
- At wrap-up time for the entire capability

### E2E Spec Structure

Follow the existing spec conventions in `playwright-e2e/tests/`:

```typescript
/**
 * <capability> — <One-line description>
 *
 * Reads { sarahEmail, sarahPassword, tenantName, ... } from state (written by globalSetup).
 * Navigation uses names/labels only — no IDs stored or used.
 *
 * Flow:
 *   §1  <Section description>
 *   §2  <Section description>
 *
 * howto reference: guides/howtos/howto_<capability>.md §1–§N
 */
import { expect, test } from "@playwright/test";
import { expectFlash, lvFill, videoGap, waitForLiveView } from "./helpers.js";
import { loadState } from "./test-state.js";

const CONSTANT_VALUES = "...";

test.describe.serial("<Capability Name>", () => {
  test.beforeEach(async ({ page }) => {
    const { sarahEmail, sarahPassword, tenantName } = loadState();
    if (!sarahEmail) throw new Error("sarahEmail missing in state — run sign-up spec first");
    if (!tenantName) throw new Error("tenantName missing in state — run tenant-setup spec first");

    await page.context().clearCookies();
    await page.goto("/auth/sign-in");
    await waitForLiveView(page);
    await lvFill(page, "#user_email", sarahEmail);
    await lvFill(page, "#user_password", sarahPassword ?? "devpassword123");
    await page.getByRole("button", { name: "Sign in" }).click();
    await page.waitForURL("**/app**", { timeout: 20_000 });

    await page.goto("/app/tenants");
    await waitForLiveView(page);
    await page.getByRole("button", { name: "Open options", exact: true }).click();
    await page.getByRole("menuitem", { name: new RegExp(`[Ss]witch to ${tenantName}`) }).click();
    await page.waitForURL(/\/app(\/datalakes)?$/, { timeout: 20_000 });
    await waitForLiveView(page);
  });

  // ─── §1 <Section Title> ─────────────────────────────────────────────────────

  test("§1 — <section description>", async ({ page }) => {
    // Navigate, interact, assert
    await videoGap(page, 1500); // pause for readable MP4 recording
  });
});
```

### E2E Spec Key Conventions

- **`videoGap(page, 1500)`** — Insert after visually meaningful moments (page loads, form submissions,
  flash messages) so the auto-recorded MP4 is watchable. Typically 1200–1500ms.
- **`waitForLiveView(page)`** — Always call after navigation to ensure the LiveView WebSocket is connected
- **`lvFill(page, selector, value)`** — Use instead of `page.fill()` to trigger LiveView `phx-change` events
- **`expectFlash(page, message)`** — Assert flash message and pause for video
- **`loadState()`** — Read pre-computed state from `e2e-state.json` (written by `globalSetup`). Specs NEVER call `saveState()` — all state is generated upfront.
- **Navigation by label** — Always use `getByRole`, `getByText`, `getByLabel` — never CSS selectors with IDs
- **`howto reference:`** — Link back to the guide section in the spec's JSDoc header

### E2E State Architecture

State is managed by `globalSetup` (`playwright-e2e/tests/setup-state.ts`), NOT by individual specs:

- **`globalSetup`** runs once before all tests, generates a `runId` from `Date.now()`, computes ALL
  names/emails with the run ID suffix, and writes the complete `playwright-state/e2e-state.json`.
- **Specs only call `loadState()`** — they NEVER call `saveState()` or `getRunId()`.
- **`RECORD_MODE=true`** uses fixed clean names (no suffix) for video recording on a clean DB.
- Each spec is independently runnable as long as the platform state exists (user registered, tenant
  created, etc.) — no sequential dependency between specs for state propagation.

### Guide Update Patterns

When comparing guide text with the live UI during a walkthrough:

1. **Read the guide section** before each manual verification step
2. **Compare systematically**: route, form fields, field types, validation messages, flash text,
   button labels, page titles, subtitles
3. **Log discrepancies** with severity (LOW/MEDIUM/HIGH) in the session doc
4. **Fix guide text immediately** — don't batch fixes; edit the guide as you discover issues
5. **Fix code bugs separately** — copy-paste artifacts (e.g. wrong subtitle), incorrect field
   validations, stale option lists are code bugs, not guide issues. Fix them in the source and
   note in the session log.

Common discrepancies to watch for:
- Data type lists that don't match `<select>` options in the UI
- Fields described as "optional" that are actually required (or vice versa)
- UI descriptions that are copy-paste artifacts from other pages
- "Always maintains at least one row" vs "starts empty with Add button"

### E2E Debugging — LiveView Timing

LiveView forms have specific timing requirements that cause E2E flakiness:

1. **`selectOption` on `<select>` elements** — MUST be followed by `waitForLiveView(page)` before
   the next action. Without this, the `phx-change` event may not be processed before the form
   re-renders, causing the dropdown to reset to its default value.
2. **`pc-switch` checkboxes** — The hidden `<input type="checkbox">` is behind a `<label class="pc-switch">`.
   Use `page.locator("label:has(#field_id)").click()` instead of clicking the checkbox directly.
3. **`videoGap` before page transitions** — Add `await videoGap(page, 3000)` before any click that
   causes navigation (Create Table, Sign out, Cancel, tab switches) so the current page state is
   visible for ~3 seconds in headed mode.
4. **Column index stability** — When adding multiple columns to a generic table form, column indices
   (0, 1, 2...) are stable as long as you add fields sequentially and don't delete/reorder. Always
   `waitForLiveView(page)` after clicking "Add Field" before filling column fields.

### When to Register in playwright.config.ts

If creating a new spec file, add a project entry in `playwright-e2e/playwright.config.ts`:

```typescript
{
  name: "<capability>",
  testMatch: /<capability>\.spec\.ts/,
  use: { ...devices["Desktop Chrome"] },
},
```

---

## Phase 5: When Stuck Protocol

Stop immediately and ask:

```
We're stuck at step [N]: <describe what happened and what was expected>

A) Fix it now
   Say "investigate" and I'll check server logs / DB state, or describe the fix directly.

B) File a GitHub issue and continue
   Suggested title: "<BUG: concise description>"
   I'll file it under milestone [name] with screenshots, then continue from the next step.
```

### If Human Chooses A — Investigate

Use Tidewave if available:
- `get_logs` — tail 20, look for errors
- `execute_sql_query` — check relevant table for the row
- `project_eval` — inspect changesets or structs

Report findings clearly, then wait for instruction.

### If Human Chooses B — File Issue

```bash
gh issue create \
  --title "BUG: <concise description>" \
  --label "bug" \
  --milestone "<milestone number>" \
  --body "$(cat <<'EOF'
## Summary
<What went wrong — one paragraph>

## Steps to Reproduce
(from walkthrough guide: guides/howtos/howto_<capability>.md — Step <N>)

1. Navigate to `<route>`
2. <actions>

## Expected Behavior
<What should happen>

## Actual Behavior
<What happened instead>

## Screenshot
![Bug screenshot](assets/screenshots/<CAPABILITY_NAME>/<N>-<slug>.png)

*Full guide in progress: `guides/howtos/howto_<capability>.md`*
*Branch: `<current-branch>`*
EOF
)"
```

After filing, update the guide section status:

```markdown
### Status
BUG — [#<number>](<url>): <one-line description>
```

Then continue to the next step.

---

## Phase 6: Wrap Up

When human says "done", "wrap up", or "finish":

### Step 6.1: Generate Table of Contents

Scan all `## <N>.` headings in the guide and replace the ToC placeholder:

```markdown
## Table of Contents

1. [Section Title](#1-section-title)
2. [Section Title](#2-section-title)
...
```

### Step 6.2: Add Prerequisites Section (if needed)

If the walkthrough required seed data, other capabilities, or specific configuration, add
before the first section:

```markdown
## Prerequisites

- [ ] Datalake created and status "Ready" (see [How to Manage Data Lakes](howtos/howto_manage_datalakes.md))
- [ ] Tenant admin access
```

### Step 6.3: Add Summary

Append at the end of the guide:

```markdown
---

## Summary

| Step | Capability | Status |
|------|------------|--------|
| 1 | <title> | PASSED |
| 2 | <title> | BUG [#N](url) |

**Issues filed:** [#N](url), [#N](url)

**E2E spec:** `playwright-e2e/tests/<capability>.spec.ts`
```

### Step 6.4: Finalize E2E Spec

If a spec was created or edited during the session:

1. Ensure all `§N` tests cover the guide sections
2. Ensure `howto reference:` in the JSDoc header matches the guide
3. If the spec introduces new state values (new user, new resource name), add them to
   `setup-state.ts` globalSetup — specs NEVER call `saveState()` directly
4. Register in `playwright.config.ts` if new
5. Ask the human: "Want me to run the E2E spec now? (`pnpm test --headed --project=<capability>`)"

### Step 6.5: Collect Recordings

After running the E2E spec (if applicable):

```bash
# Find recordings from the test run
find playwright-e2e/test-results -name "*.webm" -path "*<capability>*"

# Copy to guide assets
cp <each-recording> guides/assets/recordings/<CAPABILITY_NAME>/<N>-<slug>.webm
```

Update guide sections with video embeds where recordings are available.

**Combine into a single MP4** (for PR comments, Slack, or a unified walkthrough video): follow the webm→mp4 concat recipe in `/ui:playwright-pair-program` Phase 6.5 — one shared ffmpeg pipeline for both skills.

### Step 6.6: Register in mix.exs

If not already registered:
1. Add `"guides/howtos/howto_<capability>.md"` to `extras:` list
2. Add to the matching group in `groups_for_extras:`

### Step 6.7: Verify with mix docs

```bash
mix docs
# Opens doc/index.html — check guide appears and screenshots load
```

### Step 6.8: Commit

```bash
git add guides/howtos/howto_<capability>.md guides/assets/screenshots/<CAPABILITY_NAME>/ guides/assets/recordings/<CAPABILITY_NAME>/
git add playwright-e2e/tests/<capability>.spec.ts playwright-e2e/playwright.config.ts
# If mix.exs was updated:
git add mix.exs
git commit -S -m "docs: GH-NNN add howto + E2E spec for <capability>"
```

---

## Guide Quality Checklist

- [ ] Every step has a screenshot with meaningful alt text
- [ ] All screenshots are in `guides/assets/screenshots/<CAPABILITY_NAME>/`
- [ ] Screenshot paths use `assets/screenshots/...` (ExDoc-compatible)
- [ ] Recordings collected from test-results to `guides/assets/recordings/<CAPABILITY_NAME>/`
- [ ] Video embeds added to guide sections where recordings exist
- [ ] `mix.exs` `extras:` includes this guide
- [ ] `mix.exs` has `assets: %{"guides/assets" => "assets"}` configured
- [ ] Every broken step has a `BUG — [#N](url)` status
- [ ] Table of Contents matches all `## N.` headings
- [ ] `mix docs` builds without warnings about missing images
- [ ] E2E spec registered in `playwright.config.ts`
- [ ] E2E spec `howto reference:` matches guide sections
- [ ] E2E spec uses `videoGap()` for readable auto-recorded MP4s

---

## ExDoc Asset Reference Rules

ExDoc ~0.40 resolves images/videos in extras using the `assets:` map.

| Where asset lives | Reference in markdown |
|---|---|
| `guides/assets/screenshots/foo/01-bar.png` | `![alt](assets/screenshots/foo/01-bar.png)` |
| `guides/assets/recordings/foo/01-bar.webm` | `<video>` tag with `src="assets/recordings/foo/01-bar.webm"` |
| `guides/assets/images/diagram.png` | `![alt](assets/images/diagram.png)` |

**Do NOT** use absolute paths or external URLs for guide screenshots — they won't
render in the offline ExDoc output. Cloudflare Stream iframes are the exception for
production-quality video embeds.

---

## Tool Reference

| Tool | When to Use |
|---|---|
| `browser_navigate` | Go to a URL |
| `browser_snapshot` | See current state before acting |
| `browser_click` | Click (explicit instruction only) |
| `browser_type` / `browser_fill_form` | Fill a field (explicit instruction only) |
| `browser_take_screenshot` | Capture screenshot for the guide |
| `browser_network_requests` | Capture API calls observed |
| `browser_wait_for` | Wait for text or redirect |
| `gh issue create` | File a bug as a GitHub sub-issue |
| `git branch --show-current` | Get current branch for issue linking |

### Tidewave (when available)

| Tool | When to Use |
|---|---|
| `get_logs` | Check server logs when a step fails |
| `execute_sql_query` | Verify DB state after form submit |
| `project_eval` | Inspect Elixir structs or changesets |
| `get_source_location` | Find which LiveView module handles a route |
