# atomic-fi JDM editor

Local JDM (JSON Decision Model) authoring + simulation tool for atomic-fi,
with an optional AI copilot for natural-language rule authoring.

Vendored from [gorules/editor](https://github.com/gorules/editor) at upstream
SHA `1a413b3d47e8dab56d85fbd62d9b9a795d57ca6a`. Frontend only — the editor
talks to two local services: ZenRule (rule evaluation) and Phoenix (rule
CRUD). With the optional AI copilot enabled, it also talks to a small Node
sidecar that brokers LLM calls.

## Prerequisites

- Node 22+ and pnpm
- Docker (for the ZenRule agent)
- Elixir 1.18 / OTP 27 (for the Phoenix backend) — or an existing
  atomic-fi Phoenix dev environment
- `pnpm install` run once at the repo root

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  Browser (Vite dev: http://localhost:5173)                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  jdm-editor SPA (this package)                           │  │
│  │   - Visual graph editor (gorules/jdm-editor)             │  │
│  │   - Simulator panel                                       │  │
│  │   - Optional CopilotChat side panel (AI rule authoring)   │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
         │ /api/copilotkit ──── Vite proxy ──┐
         │ /api/rules        ── Vite proxy ──┼──▶ Phoenix :4100  (rule CRUD)
         │ /api/projects     ── Vite proxy ──┼──▶ ZenRule :8090  (evaluate)
                                             │
                                             ▼ (sidecar, only when copilot enabled)
                            ┌────────────────────────────────────┐
                            │  jdm-copilot-runtime :4111         │
                            │   LLM broker (OpenAI / Anthropic)  │
                            └────────────────────────────────────┘
```

## Configuration

Copy the example env and fill in your Phoenix API key:

```bash
cp .env.example .env.local
```

Edit `.env.local`:

```env
VITE_ATOMIC_FI_API_KEY=<your phoenix x-api-key>
```

The Phoenix REST endpoints require this key on every request (set as the
`x-api-key` header by the axios client).

## Quickstart (without AI copilot)

Three terminals from the repo root:

```bash
# Terminal 1 — ZenRule (rule evaluator, port :8090)
docker compose -f local-dependencies.yaml up -d zenrule

# Terminal 2 — Phoenix (rule CRUD, port :4100)
mix phx.server

# Terminal 3 — the editor (port :5173)
pnpm --filter @atomic-fi/jdm-editor dev
```

Open the printed Vite URL (usually `http://localhost:5173`). You'll land
on the rules index. Pick a rule type (Onboarding or Transaction screening)
and click any rule to enter the editor, or click **New rule** to start
fresh.

## Quickstart (with AI copilot)

Add a fourth terminal — the CopilotKit sidecar. See
`example-apps/jdm-copilot-runtime/README.md` for the full doc; the short
version:

```bash
# Terminal 4 — copilot sidecar (port :4111)
cp example-apps/jdm-copilot-runtime/.env.example example-apps/jdm-copilot-runtime/.env.local
# Edit OPENAI_API_KEY (or set LLM_PROVIDER=anthropic + ANTHROPIC_API_KEY)
pnpm --filter @atomic-fi/jdm-copilot-runtime dev
```

Reload the browser. On any rule-edit page (`/rules/:ruleType/:filename`)
you'll see a **chat bubble icon** in the header — click it to open the
**Rule copilot** side panel. The editor squeezes; the chat docks on the
right. Click the icon again (or the `✕` in the panel) to close.

## Using the editor

### Manual authoring

- **Open** an existing rule via the index page (`/rules/onboarding` or
  `/rules/transaction-screening`).
- **Edit** rules visually — drag node types from the right-side
  Components panel onto the canvas.
- **Save** via the toolbar Save button. Phoenix writes the JSON under
  `priv/zenrule/<rule_type>/<name>.json`.
- **Simulate** the saved rule via the editor's built-in Simulator panel
  (bottom of the canvas). It calls ZenRule, which evaluates the file as
  it exists on disk (so save first; the agent re-reads with ~5s poll).

### AI rule copilot

Open the chat panel and describe a rule in plain English. The agent
will:

1. Read the current rule's metadata, the JDM cheatsheet, and the
   payload schema (everything available via `useCopilotReadable`).
2. Emit a sequence of tool calls: `add_node` (input → decision table
   → output), `add_edge` between them, `save_rule`, and optionally
   `simulate_rule`.
3. Each tool call surfaces a **preview card** in the chat. Click
   **Apply** to execute or **Reject** to push back. The agent sees
   rejections as tool results and self-corrects.

Available actions the agent can call:

| Action | What it does |
|---|---|
| `add_node` | Adds an input/output/decision-table/etc node; auto-positions if you don't pass a `position` |
| `update_node` | Targeted patch — name, content, or position. Accepts node id OR exact node name |
| `remove_node` | Deletes a node and any edges touching it |
| `add_edge` | Connects two nodes (by id OR name) |
| `remove_edge` | Disconnects two nodes |
| `save_rule` | Writes the current graph to disk via Phoenix |
| `create_rule` | Navigates to a blank editor for a new rule file |
| `rename_rule` | Saves under a new filename and deletes the old |
| `delete_rule` | Irreversible — type-to-confirm card |
| `open_rule` | Switches to a different rule |
| `simulate_rule` | Evaluates the last-saved rule via ZenRule against a JSON context |

When the agent emits multiple tool calls in a single turn, an **Apply
all** footer appears bottom-right (only when ≥2 cards are pending).
Click it to chain through them one-by-one — CopilotKit serializes the
calls, so cards beyond the first show "queued — waiting for previous
tool to finish" until they're promoted.

### Example prompts

See `example-rulesets/prompts.md` for ten ready-to-paste prompts spanning
KYC gating, sanctions, beneficial-ownership disclosure, structuring
detection, and more.

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Chat opens but agent never replies | Sidecar isn't running, or the LLM key is unset. Check `curl http://localhost:4111/healthz` and the sidecar terminal logs. |
| `Save` 401s | `VITE_ATOMIC_FI_API_KEY` not set in `.env.local`. |
| `simulate_rule` returns "rule not found" / 404 | Rule hasn't been picked up by ZenRule yet. Save first, wait ~6s, then simulate. |
| `simulate_rule` 422 | The rule failed ZenRule's compile step. The card shows the full ZenRule error message + JSON body — read it for the exact failure (typically a malformed cell expression). |
| `add_edge` shows `(unresolved: ...)` | The agent passed an id or name that matches no current node. Usually means it referenced a node that hasn't been added yet (parallel tool calls in the same turn). Ask it to use names instead. |
| Cards stay "queued" forever | CopilotKit only promotes one tool call of an action at a time. Apply the active one first; the queued ones follow. |
| Browser shows stale UI after my edits | Hard reload (Cmd-Shift-R on macOS) — HMR sometimes misses prop-level changes. |

For sidecar-side debugging, set `LOG_LEVEL=debug` in the sidecar's
`.env.local` and restart it. You'll see every tool-call arg the LLM sent.

## What works

- **Read/Write** rules via Phoenix REST (`/api/rules/...`).
- **List** rules per rule type from the index page.
- **Simulate** any saved rule against a JSON context (built-in panel or
  agent `simulate_rule` action).
- **AI authoring** end-to-end via the optional copilot.
- **Theme** toggle (light / dark / auto) via the header bulb icon.

## What does not work yet

- **Simulating unsaved drafts.** ZenRule only evaluates files on disk;
  the workflow stays **Save → Simulate** (see `TODO(draft-state)` in
  `src/helpers/simulator.ts`).
- **Concurrent multi-action tool calls** with full parallel UX. The
  agent loop is serialized one tool at a time per action (a CopilotKit
  constraint). The Apply-all footer chains through them sequentially.

## Upstream divergence

Modifications from upstream (`gorules/editor` @ pinned SHA):

- Stripped Rust backend (`backend/`, `Cargo.toml`, `Dockerfile`, `Makefile`, …).
- `src/helpers/simulator.ts` is new; replaces upstream's inline axios call.
- `src/helpers/rules-api.ts` and `src/helpers/clients.ts` are new (Phoenix REST).
- `src/copilot/` is new (CopilotKit provider, actions, readables, cards).
- `vite.config.ts` proxy retargeted from `:3000` (upstream Rust) to the
  three local services; HTTPS dev-server block removed.
- `package.json` name → `@atomic-fi/jdm-editor`.
- README replaced.
- Page-header heading rebranded.

## License

Upstream `gorules/editor` is MIT (see `LICENSE`). Our modifications are
distributed under the parent atomic-fi license.
