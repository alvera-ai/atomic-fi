# JDM Editor — Copilot Architecture

Design record for the editor's AI copilot layer (`src/copilot/`). Written
**before** the CopilotKit **v2** rebuild — this documents the target
architecture, not the legacy v1 code it replaces.

Related: [`docs/adr/ADR-002-copilot-runtime-sidecar.md`](../../../docs/adr/ADR-002-copilot-runtime-sidecar.md)
(the backing runtime), repo `README.md` (whole-editor architecture).

---

## 1. Scope & principle

The editor is **thin stitching**. It owns no LLM logic and no rules engine —
it composes two third parties and adds a domain glue layer:

- **`@gorules/jdm-editor`** — the visual decision-graph canvas + simulator.
- **`@copilotkit/react-core/v2`** — the chat UI + agentic tool-call protocol.

`src/copilot/` is the glue: it exposes the editor's graph + persistence as
**CopilotKit tools** and exposes the editor's state as **agent context**. All
model inference happens off-browser in the `copilot-runtime` sidecar.

> The React layer is just the stitching: `jdm-editor` rendered inside a
> CopilotKit session. No domain intelligence lives here.

---

## 2. Container diagram (C4 level 2)

```
┌─ Browser ────────────────────────────────────────────────────────────┐
│                                                                       │
│  jdm-editor SPA  (/demo/atomic-fi-jdm-editor/, served by Phoenix)     │
│  ┌─────────────────────────────┐   ┌──────────────────────────────┐  │
│  │ <DecisionGraph>             │   │ <CopilotChat>      (/v2)      │  │
│  │   gorules canvas+simulator  │◀─▶│   chat + tool-call cards     │  │
│  └─────────────────────────────┘   └──────────────────────────────┘  │
│              ▲  src/copilot/  (glue)            ▲                     │
│              │  · useHumanInTheLoop ×11 (tools) │                     │
│              │  · useAgentContext ×7  (context) │                     │
│              └──────────────────────────────────┘                     │
└───────────────────────────────────────────────────────────────────────┘
        │ REST (x-api-key)                 │ POST {runtimeUrl}
        │ rule CRUD / simulate             │ AG-UI protocol stream
        ▼                                  ▼
┌─ Phoenix :4100 ──────────┐   ┌─ copilot-runtime :4111 ─────────────────┐
│  /api/rules   rule CRUD  │   │  Hono + @copilotkit/runtime v2          │
│  /api/projects  ZenRule  │   │  BuiltInAgent (Factory Mode, "aisdk")   │
│       proxy → :8090      │   │  agent key: "default"                   │
└──────────────────────────┘   │  pickModel(env) → Vercel AI SDK         │
                                └─────────────┬──────────────┬───────────┘
                                              │ LLM          │ telemetry
                                              ▼              ▼
                                   openai/anthropic/   copilot-telemetry
                                   google/groq/ollama  (Vector :8686)
```

`runtimeUrl` is env-driven (§7) — the browser posts the AG-UI stream straight
to `copilot-runtime`; Phoenix is not in the copilot path.

---

## 3. `src/copilot/` module layout

```
src/copilot/
├─ copilot-provider.tsx      <CopilotKitProvider runtimeUrl> — session root
│
├─ use-editor-readables.ts   useAgentContext ×7 — editor state → agent context
│
├─ actions/                  the 11 tools, grouped by concern
│  ├─ use-graph-actions.tsx     add/update/remove_node, add/remove_edge
│  ├─ use-persist-actions.tsx   save/rename/create/delete/open_rule
│  └─ use-simulate-action.tsx   simulate_rule
│
├─ cards/                    Human-in-the-loop render surface (Ant Design)
│  ├─ preview-card.tsx          graph mutations  (Apply / Reject)
│  ├─ persist-card.tsx          side-effecting   (Save / Run / Open …)
│  ├─ destructive-card.tsx      delete_rule      (type-to-confirm)
│  └─ apply-all-footer.tsx      batch-apply queue for multi-tool turns
│
├─ tool-params.ts            NEW — loose Zod schemas w/ .describe():
│                            the LLM-facing tool contract (see §5)
│
└─ DOMAIN — carried verbatim, no CopilotKit coupling:
   ├─ node-types.ts            strict Zod arg schemas (in-render validation)
   ├─ payload-schema.ts        rule-engine context schema (a readable)
   └─ jdm-cheatsheet.ts        JDM authoring guide (a readable)
```

Mounted once per editor page in `pages/decision-simple.tsx`, which calls
`useEditorReadables`, `useGraphActions`, `usePersistActions`,
`useSimulateAction` and renders `<CopilotChat>` as a sibling of
`<DecisionGraph>`.

---

## 4. CopilotKit v1 → v2 migration

The v2 surface lives under the `/v2` subpath of the same `@copilotkit/react-core`
package (1.57.4). v2 is a matched client for the `copilot-runtime` we built —
it speaks the AG-UI protocol the runtime's `createCopilotHonoHandler` serves.

| Concern        | v1                                          | v2 (target)                                              |
|----------------|---------------------------------------------|----------------------------------------------------------|
| Provider       | `<CopilotKit runtimeUrl>`                   | `<CopilotKitProvider runtimeUrl>`  (`/v2`)               |
| Chat UI        | `<CopilotChat>` from `@copilotkit/react-ui` | `<CopilotChat>` from `@copilotkit/react-core/v2`         |
| Styles         | `@copilotkit/react-ui/styles.css`           | `@copilotkit/react-core/v2/styles.css`                   |
| Editor context | `useCopilotReadable({description, value})`  | `useAgentContext({description, value})` — 1:1            |
| HITL tool      | `useCopilotAction({…, renderAndWaitForResponse})` | `useHumanInTheLoop({…, render})`                   |
| Tool params    | `parameters: [{name,type,required,…}]`      | `parameters: ZodSchema` (StandardSchemaV1)               |
| Render         | `({args,status,respond}) => JSX` (function) | `render: ComponentType<unionProps>`                      |
| Status         | string `'inProgress'|'executing'|'complete'`| `ToolCallStatus` enum (same string values)               |
| `respond`      | `respond?.(result)`                         | `respond(result): Promise<void>` — defined only in `Executing` |
| Agent select   | implicit default flow                       | `agentId="default"` — matches runtime's agent key        |

`@copilotkit/react-ui` is dropped entirely; the chat component now ships from
the core package's `/v2` export.

---

## 5. Tool-call lifecycle (Human-in-the-Loop)

Every one of the 11 tools is **Human-in-the-Loop**: the agent proposes, a card
renders, the user Applies or Rejects, and the user's decision *is* the tool
result. No tool runs without an explicit click.

```
user prompt
   │
   ▼
copilot-runtime  ── streams a tool call ──▶  useHumanInTheLoop.render
   │                                              │
   │   ToolCallStatus.InProgress  args: Partial<T> │  card: "pending", no buttons
   │   ToolCallStatus.Executing   args: T          │  card: Apply / Reject live
   │                                respond: fn    │
   │                                              ▼
   │                              user clicks ──▶ domain validation
   │                                              │  (node-types.ts safeParse,
   │                                              │   duplicate-name, cycle, …)
   │                                              ▼
   │                              setGraph(…) / saveRule(…) / navigate(…)
   │                                              │
   │◀──────── respond({accepted, …, reason}) ─────┘
   │
   ▼   ToolCallStatus.Complete   result: string    card: "resolved" (read-only)
agent sees the result, self-corrects on {accepted:false, reason}
```

**Why two schemas (the `tool-params.ts` split).** v2 has no array-of-params
form — `parameters` takes one Zod schema, used both to build the LLM's tool
JSON-schema and to parse tool-call args. We keep v1's separation of concerns:

- **`tool-params.ts`** — *loose* schemas with `.describe()` on each field.
  This is the **LLM-facing contract** — what the model sees. No `.transform`
  or hard refinements, so a malformed arg never hard-fails before `render`.
- **`node-types.ts`** — the *strict* schemas (transforms, refinements,
  tolerant preprocessing). Still `safeParse`'d **inside each `render`**, against
  the live graph. A failure renders an error card whose `reason` is fed back
  via `respond`, so the model self-corrects — the v1 behavior, preserved.

`render` components are registered with a stable identity (`deps: []`) and read
mutable editor state through refs, so card-local state (idempotency guards)
survives parent re-renders.

---

## 6. The 11 tools

| Tool          | Group   | Card              | Effect                                        |
|---------------|---------|-------------------|-----------------------------------------------|
| `add_node`    | graph   | PreviewCard       | append node; auto-positions if no `position`  |
| `update_node` | graph   | PreviewCard       | patch name/content/position; id **or** name   |
| `remove_node` | graph   | PreviewCard       | delete node + touching edges                  |
| `add_edge`    | graph   | PreviewCard       | connect two nodes; id **or** name             |
| `remove_edge` | graph   | PreviewCard       | disconnect by edge id                         |
| `save_rule`   | persist | PersistCard       | write graph → Phoenix; refuses on cycle       |
| `rename_rule` | persist | PersistCard       | save-as new name, delete old, navigate        |
| `create_rule` | persist | PersistCard       | navigate to blank editor                      |
| `delete_rule` | persist | DestructiveCard   | irreversible disk delete (type-to-confirm)    |
| `open_rule`   | persist | PersistCard       | navigate to another rule                      |
| `simulate_rule`| sim    | PersistCard       | evaluate last-saved rule via ZenRule          |

---

## 7. Agent context (the 7 readables)

`useEditorReadables` publishes editor state to the agent via `useAgentContext`:

current rule metadata · the full decision graph · valid `rule_type` values ·
the rule-engine payload schema (`payload-schema.ts`) · the JDM authoring
cheatsheet (`jdm-cheatsheet.ts`) · the last simulation result · existing rule
filenames (collision avoidance).

---

## 8. Configuration

`runtimeUrl` is env-driven so the editor can target the standalone
`copilot-runtime` sidecar without a code change:

```
VITE_COPILOT_RUNTIME_URL   →  <CopilotKitProvider runtimeUrl>
  unset (default)          →  "/api/copilotkit"   (same-origin)
  local sidecar            →  "http://localhost:4111/api/copilotkit"
```

The runtime's behaviour (provider, model, telemetry) is owned by
`external-deps/copilot-runtime/docker.env` — see ADR-002.

---

## 9. File inventory

| File                                 | Action  | Notes                                  |
|---------------------------------------|---------|----------------------------------------|
| `copilot-provider.tsx`                | rewrite | v2 `<CopilotKitProvider>`              |
| `use-editor-readables.ts`             | rewrite | `useAgentContext` ×7                   |
| `actions/use-graph-actions.tsx`       | rewrite | `useHumanInTheLoop` ×5                 |
| `actions/use-persist-actions.tsx`     | rewrite | `useHumanInTheLoop` ×5                 |
| `actions/use-simulate-action.tsx`     | rewrite | `useHumanInTheLoop` ×1                 |
| `cards/*.tsx`                         | edit    | `status` prop → `ToolCallStatus` enum  |
| `tool-params.ts`                      | new     | loose LLM-facing Zod schemas           |
| `node-types.ts` `payload-schema.ts` `jdm-cheatsheet.ts` | keep | domain — verbatim       |
| `pages/decision-simple.tsx`           | edit    | `<CopilotChat>` from `/v2`; v2 `labels`|
| `app.tsx`                             | keep    | mounts `<CopilotProvider>` unchanged   |
