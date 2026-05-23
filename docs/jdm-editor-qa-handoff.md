# JDM Editor — QA Handoff

Handoff for a separate session that adds Playwright coverage + a manual-QA
walkthrough for the **atomic-fi JDM editor** (`example-apps/atomic-fi-jdm-editor`)
and its CopilotKit copilot. Self-contained — read just this file to start.

Method is adapted from the `platform` repo's QA skills
(`platform/.claude/commands/ui/feature-walkthrough.md`, `qa/pair-qa.md`,
`ui/playwright-pair-program.md`), retuned for atomic-fi.

---

## PART 1 — What shipped on `feat/gh-49-single-app-demo-build`

GH-49 collapsed local dev into one Phoenix app + local Ollama + 2 Docker
services. 19 commits off `main`:

```
   demo plumbing
     Plug.Static serves priv/static/demo/*  ·  home page lists demos
     each example app's vite build → priv/static/demo/<app>/ (watchers)
   parser
     POST /api/parse — JSON+base64 controller; app/schemas.py ported to
     Elixir JSON Schemas; poppler rasterises PDFs; ReqLLM drives Ollama
     onboarding-flow repointed /extract → /api/parse
   copilot
     POST /api/copilotkit — CopilotKit Runtime Protocol passthrough
     editor replaced with the worktree copy; Node runtime pruned
   ops
     Lotus AI → Ollama; GOOGLE_API_KEY refs dropped; Make/README cleanup
   this session (commit 0505faf)
     onboarding API-key gate + Elixir e2e ports; Playwright verification
     of onboarding-flow + lotus-embed; parser settled on ReqLLM
     json_schema mode + llama3.2-vision:11b
```

Bugs fixed this session: `api.ts` nested `legal_entity.id`; e2e specs
(`account_holder_type`, no `GET /api/legal-entities/:id`); parser
`:tool_strict` → `:json_schema` mode; thinking-model → non-thinking VLM;
slow-inference timeouts; exact-extraction asserts → pipeline checks.

---

## PART 2 — Verified state

```
   demo app                Playwright       status
   ───────────────────────────────────────────────────────────────
   onboarding-flow          3 specs          2 ✓ · 1 skip (stale path)
   lotus-embed              6 specs          6 ✓
   atomic-fi-jdm-editor     NONE             UNVERIFIED  ← this handoff
```

Runtime topology (see `guides/architecture.md` § "AI Features"):

```
   make run-backing-services → ZenRule :8090 · Watchman :8084 (Docker)
   make server               → Phoenix :4100 + vite build watchers
   ollama serve              → :11434
       llama3.2-vision:11b   parser   (non-thinking — required)
       qwen3.5:9b            copilot + Lotus SQL  (thinking)
```

`config/dev.secret.exs` (gitignored) overrides copilot → `qwen3.5:9b`.
`/api/copilotkit` config: `config :atomic_fi, :copilotkit`.

---

## PART 3 — JDM-editor QA playbook (adapted from platform skills)

### 3.1 Deliverables (co-produced from one session)

1. **How-to guide** — `guides/howtos/howto_jdm_editor.md` (new; atomic-fi
   has no `howtos/` yet — create it, register in `mix.exs` `extras:`).
   Screenshots under `guides/assets/screenshots/jdm-editor/`.
2. **E2E spec** — `example-apps/atomic-fi-jdm-editor/e2e/jdm-copilot.spec.ts`
   + a new `example-apps/atomic-fi-jdm-editor/playwright.config.ts`.
3. **GitHub sub-issues** — filed for every blocker found.

### 3.2 Mandatory rules (from feature-walkthrough / pair-qa)

- **Human leads, Claude follows.** Never click / fill / navigate without an
  explicit instruction. Screenshot after each documented step.
- **Manual walk BEFORE editing specs.** Order is always: drive it live →
  update guide → write/update spec. Never write a spec and iterate on
  failures hoping it works.
- **Headed browser always** — the walkthrough is collaborative; an
  invisible browser is useless.
- **When stuck — STOP and ASK.** Two choices: (A) fix now, or (B) file a GH
  sub-issue and continue. Never autonomously fix or skip.
- **Session log is non-negotiable** — `docs/playwright-sessions/jdm-editor.md`,
  updated after every step / blocker / fix, not at the end.
- **Commits** — GPG-signed (`-S`), conventional prefix, no `Co-Authored-By`,
  mention `GH-49`. `mix format` + `mix credo --strict` before commit.

### 3.3 Failure buckets (from pair-qa) — classify before fixing

```
   A Flake          transient; re-run once. Saw this with lotus-embed
                    test 2 — stale iframe state after the prior test.
   B Intentional    label/route/field changed on purpose → spec-side fix
   C Stale locator  spec assumption outdated, app correct → spec-side fix
   D Regression     app behaviour wrong → code-side fix, spec stays
```

Present the bucket + evidence + one recommendation, then wait for the human.

### 3.4 What's DIFFERENT from the platform skills

The platform skills target a **Phoenix LiveView** app. The JDM editor is a
**React SPA** — so:

```
   DROP   lvFill · waitForLiveView · phx-change · [data-phx-main]
   USE    plain Playwright — getByRole / getByText / click / fill,
          Playwright's own auto-waiting
   KEEP   Tidewave MCP for server-side inspection (atomic-fi has the
          tidewave dep): get_logs, project_eval, get_source_location.
          Use it to read /api/copilotkit streaming errors server-side.
```

The embedded Lotus dashboard *is* LiveView — but that's `lotus-embed`, a
different app, already covered.

### 3.5 Session shape

```
   Phase 1  init — branch context, create guide stub + session log,
                   scaffold playwright.config.ts (don't write spec yet)
   Phase 2  bootstrap — make run-backing-services + make server + ollama;
                   confirm /demo/atomic-fi-jdm-editor/ serves 200
   Phase 3  walkthrough — human drives the editor + copilot; Claude
                   screenshots + writes the guide per step
   Phase 4  spec — scaffold e2e/jdm-copilot.spec.ts once the flows are
                   known; verify each locator live before writing it
   Phase 5  stuck protocol — fix-now or file-issue, never skip
   Phase 6  wrap — ToC, status table, run the spec, commit
```

---

## PART 4 — JDM editor specifics

### 4.1 The app

```
   example-apps/atomic-fi-jdm-editor/   pkg @atomic-fi/jdm-editor
   served   http://localhost:4100/demo/atomic-fi-jdm-editor/
   stack    React SPA (vite base /demo/atomic-fi-jdm-editor/)
   REST     src/helpers/clients.ts — atomic-fi REST needs x-api-key
            (check for an API-key gate at startup, like onboarding's
             ConnectGate — verify in src/ first thing)
   copilot  src/copilot/copilot-provider.tsx
              <CopilotKit runtimeUrl="/api/copilotkit">
            src/copilot/actions/  — use-graph-actions (add/remove nodes
              + edges), use-persist-actions (save/load rules),
              use-simulate-action (simulate)
            src/copilot/cards/    — CopilotKit preview cards
```

### 4.2 The copilot backend

```
   POST /api/copilotkit   AtomicFiWeb.CopilotkitController
     CopilotKit GraphQL Runtime Protocol — 3 ops:
       availableAgents / loadAgentState     one-shot JSON
       generateCopilotResponse              multipart/mixed stream
                                            (GraphQL incremental delivery)
   model    qwen3.5:9b (thinking) via config :atomic_fi, :copilotkit
   needs    ZenRule :8090 up — save_rule / simulate_rule hit the engine
   state    client-tool round-trips are chained HTTP POSTs (no WebSocket);
            conversation state lives in the messages array
   tests    test/atomic_fi_web/controllers/copilotkit_controller_test.exs
            test/atomic_fi_web/copilotkit/incremental_test.exs
            (controller + encoder unit tests exist; NO browser e2e)
```

### 4.3 Suggested spec coverage (`jdm-copilot.spec.ts`)

```
   §1  editor loads at /demo/atomic-fi-jdm-editor/, canvas renders
   §2  open copilot panel, prompt "add a number input node called amount"
       → generateCopilotResponse streams → ActionExecution (add_node)
       → React runs the action → node appears on canvas
       → React POSTs /api/copilotkit again with the tool result
   §3  save a rule  → save_rule action → persists via ZenRule
   §4  simulate a rule → use-simulate-action → result streamed back
   §5  (controller smoke) POST /api/copilotkit availableAgents → JSON shell
```

### 4.4 Gotchas to plan for

- **Slow streaming** — `qwen3.5:9b` is a thinking model; a copilot turn
  runs minutes. Use `test.setTimeout(600_000)` and per-wait timeouts up to
  ~`540_000` (lotus-embed test 3 needed this).
- **Flaky first run** — a Playwright failure may pass on a clean re-run
  (bucket A). Re-run once before diagnosing.
- **No globalSetup state** — atomic-fi e2e specs don't use the platform's
  `e2e-state.json`. Mirror the existing pattern: read
  `priv/repo/.bootstrap_creds.json` (`rootApiKey: "alvera_root_api_key_dev"`)
  if the editor needs an API key; copy the helper shape from
  `example-apps/onboarding-flow/e2e/connect.ts`.
- **Unknown editor DOM** — inspect `src/components/` + `src/pages/` for
  stable selectors (the editor is a graph canvas — node/edge selectors may
  need `data-testid`s added; that itself may be a bucket-D finding).
- **The copilot was never browser-tested** — expect to find real bugs in
  the streaming / action round-trip, exactly as the parser was broken
  until this session. Budget for fixes, not just spec-writing.

### 4.5 New-spec wiring

```
   new: example-apps/atomic-fi-jdm-editor/playwright.config.ts
          testDir: "./e2e"
          use.baseURL: "http://localhost:4100/demo/atomic-fi-jdm-editor/"
          headless, screenshot: "only-on-failure"
          (copy from example-apps/lotus-embed/playwright.config.ts)
   new: example-apps/atomic-fi-jdm-editor/e2e/jdm-copilot.spec.ts
   run: cd example-apps/atomic-fi-jdm-editor && pnpm exec playwright test
        (requires `make server` already up)
```

---

## Quick reference

```
   creds      priv/repo/.bootstrap_creds.json
   parser     POST /api/parse        llama3.2-vision:11b (non-thinking)
   copilot    POST /api/copilotkit   qwen3.5:9b (thinking, streamed)
   architecture   guides/architecture.md § "AI Features — the LLM provider"
   platform skills (method source)
     ~/work/alvera-ai/platform/.claude/commands/ui/feature-walkthrough.md
     ~/work/alvera-ai/platform/.claude/commands/qa/pair-qa.md
     ~/work/alvera-ai/platform/.claude/commands/ui/playwright-pair-program.md
```
