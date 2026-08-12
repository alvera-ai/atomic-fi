---
name: forge-example-app
description: User-invocable wrapper that turns a natural-language use case (a compliance / payment demo to build) into a complete runnable React + TS + Vite + Tailwind + shadcn/ui app under `example-apps/<slug>/`. Every scaffolded app is a three-tab atomic-fi demo shell — Demo (use-case UI), Rule (`@gorules/jdm-editor` + CopilotKit chat), Audit (Lotus iframe) — with bearer-auth login at boot. Use whenever the user wants to scaffold a one-shot demo, reference app, or example app from a description — including phrases like "build me a demo", "scaffold an example app", "make a one-shot app", "create a payments console", "stand up a KYC playground", "give me a demo of X". This skill is a thin wrapper: it pre-flights the sidecars Phoenix (:4100), ZenRule (:8090), copilot-runtime (:4242), confirms the slug + rule_type with one quick AskUserQuestion when intent is ambiguous, then dispatches the `forge-example-app` agent via the Task tool to do the heavy lifting in an isolated context (which keeps multi-MB OpenAPI extractions, pnpm install logs, and zenrule-author back-and-forth out of the main conversation). When the agent returns, surfaces its report and the concrete commands to run the new app. Never commits — leaves the working tree dirty for human review.
when_to_use:
  - The user wants to scaffold a complete example app from an English description
  - Building a demo / reference / playground app for the atomic-fi platform
  - Wiring a new compliance use case into a runnable UI without hand-writing the boilerplate
related_artifacts:
  - example-apps/<slug>/                         (the generated app)
  - priv/zenrule/<rule_type>/<rule_name>.json    (the rule the Rule tab will load)
  - example-apps/atomic-fi-jdm-editor/example-rulesets/test-inputs.md  (rule test matrix)
  - pnpm-workspace.yaml                          (new app appended)
---

# forge-example-app

Turn a natural-language use case ("build me a payments console where ...") into a runnable atomic-fi demo app, with the JDM rule authored, the editor + CopilotKit chat + Lotus audit panels all wired, and `pnpm run build` green. **You are the dispatcher**, not the implementer — the `forge-example-app` agent does the heavy lifting in an isolated context so it doesn't pollute this conversation.

## Workflow

### 1. Restate what you heard

Echo the use case back in one sentence — gives the user a chance to redirect before any work happens. Example:

> "Building a payments console where staff send money between customers, with KYC + amount blocks and a Lotus audit view. Sound right?"

If the user's phrasing is genuinely ambiguous (no clear rule, no clear demo flow, no clear slug), ask **one** clarifying question via `AskUserQuestion` before continuing. Don't ask more than two — the agent itself can ask follow-ups during step 4 (`zenrule-author` delegation).

### 2. Pre-flight the sidecars

```bash
curl -sf --max-time 5 http://localhost:4100/api/openapi > /dev/null \
  && echo "Phoenix :4100 ✓" || echo "Phoenix :4100 ✗ — start with: mix phx.server"
curl -sf --max-time 5 http://localhost:8090/ > /dev/null 2>&1 \
  && echo "ZenRule :8090 ✓" || echo "ZenRule :8090 ✗ — start: docker compose up zenrule"
curl -sf --max-time 5 http://localhost:4242/healthz > /dev/null 2>&1 \
  && echo "copilot-runtime :4242 ✓" || echo "copilot-runtime :4242 ✗ — start: docker compose up copilot-runtime"
which pnpm > /dev/null && echo "pnpm ✓" || echo "pnpm ✗ — brew install pnpm"
```

- **Phoenix down** → abort. Tell the user, don't dispatch.
- **ZenRule down** → warn loudly. Rule authoring will fail at the verification step; the agent will surface that.
- **copilot-runtime down** → warn. The app will scaffold and build; the Copilot chat sidebar in the Rule tab will be inert until the runtime is up.
- **pnpm missing** → abort. The agent's step 9 (verify) uses `pnpm install`.

### 3. Dispatch the agent

Use the Task tool with `subagent_type="forge-example-app"`. The agent's system prompt already covers slug derivation, rule_type, OpenAPI extraction, rule authoring, scaffold, and verify — pass through the user's NL prompt verbatim plus any clarifications from step 1.

```
Task(
  description="Forge example app",
  subagent_type="forge-example-app",
  prompt="<the user's NL use case, plus any clarifications from step 1, plus a note about which sidecars were warn-only at step 2 so the agent can decide whether to proceed without rule verification>"
)
```

**Do not** read the OpenAPI spec, run pnpm install, or invoke `zenrule-author` directly from this skill. That's all the agent's job — keeping it inside the child context is the whole point of the dispatch.

### 4. Surface the agent's report

The agent returns a structured report covering: slug, app dir, endpoints wired, rule path, workspace registration, build result, sidecar warnings. Show that report to the user verbatim (it's short), then add the concrete next-step commands:

```bash
# At repo root — install all workspace deps including the new app:
pnpm install

# Run the new app (vite dev server, picks a port):
pnpm --filter <slug> dev

# Or run via Phoenix watchers (after restarting `mix phx.server`):
# The new app's build is already in priv/static/demo/<slug>/
```

Remind the user that **nothing was committed** — they review `git status` and `git add` the paths they want to keep.

### 5. If the agent failed

The agent may return with `pnpm run build: red` or `rule authoring: escalated`. In that case:

- **Don't retry automatically.** A red build means a real problem; another dispatch eats more context for the same root cause.
- Read **only** the error excerpt the agent surfaced (it's short — the agent itself was told not to dump full logs).
- Offer the user three options: (a) you investigate the specific error in this conversation, (b) the user fixes manually and re-tries, (c) abort and clean up the half-built dir.

## Hard rules

- **You dispatch, you do not implement.** Anything the agent's `.md` covers (templates, OpenAPI extraction, rule authoring, build) is the agent's job. This skill's job is the framing, pre-flight, and presentation.
- **Never read the OpenAPI spec yourself.** The agent uses `jq | head` from Bash to avoid context blow-up; if you do it here in the main conversation, you defeat the isolation that's the whole point of Option B.
- **One dispatch per invocation.** Don't loop or retry. If the agent reds out, hand the error to the user.
- **Pass user-provided slug through verbatim.** If the user said "call it `payments-demo`", include that in the dispatch prompt. Don't second-guess.
- **No commits.** Same rule as the agent — leave the tree dirty for human review.

## Related

- The agent itself: `.claude/agents/forge-example-app.md`
- Templates the agent copies from: `.claude/agents/forge-example-app/templates/`
- Rule-authoring sub-skill the agent delegates to: `.claude/skills/zenrule-author/`
