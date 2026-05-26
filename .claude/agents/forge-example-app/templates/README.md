# `forge-example-app` templates

Copy-paste sources used by the `forge-example-app` agent. The agent reads these,
substitutes `__SLUG__` / `__TITLE__` / `__APP_DESCRIPTION__` → real values, and
drops them into `example-apps/<slug>/`. Edit here when the baseline stack or
pattern moves; the agent picks up the changes on its next run.

The agent is **self-sufficient**: a generated app builds even if every other
`example-apps/*` dir is empty. Existing apps are cross-references, not
dependencies.

## What every generated app is

A three-tab atomic-fi demo shell:

```
┌────────────────────────────────────────────────────────┐
│  [Demo] [Rule] [Audit]                                  │
├────────────────────────────────────────────────────────┤
│  Demo   — use-case-specific UI (the only variable)     │
│  Rule   — <DecisionGraph> + CopilotKit chat sidebar    │
│           loaded from /api/rules/<type>/<name>          │
│  Audit  — <iframe> Lotus dashboard via /api/lotus/...   │
└────────────────────────────────────────────────────────┘
```

Boot flow is the same in every app:

```
1. App() reads getStoredBearer().
2. No bearer → <LoginGate onConnected={setBearer}/>, return early.
3. Bearer present → <CopilotProvider><AppShell demo={...} ruleEditor={...} audit={...} /></CopilotProvider>
```

## Stack & version locks

| Package                          | Version  | Why locked |
|----------------------------------|----------|------------|
| `react` / `react-dom`            | 18.3.1   | `@gorules/jdm-editor@1.51.0` is known-good against React 18 |
| `@copilotkit/react-core`         | 1.57.4   | **Must equal** `@copilotkit/runtime` in `external-deps/copilot-runtime/` — AG-UI v2 wire protocol |
| `@gorules/jdm-editor`            | ^1.51.0  | Wraps React Flow internally; bundles with its own CSS |
| `@gorules/zen-engine-wasm`       | ^0.23.0  | In-browser eval; ships .wasm — needs `vite-plugin-wasm` |
| `vite-plugin-wasm`               | ^3.5.0   | Loads the zen-engine wasm module |
| `@vitejs/plugin-react-swc`       | ^4.2.3   | Matches `atomic-fi-jdm-editor`'s build setup |
| `tailwindcss` + `@tailwindcss/vite` | ^4.3.0 | v4 reads config from `@theme` in CSS, no config file |

Don't bump these in templates without bumping `external-deps/copilot-runtime/`
in lockstep (for `@copilotkit/*`) or testing `@gorules/jdm-editor` against the
new React version (for `react`).

## Layout

```
templates/
├── README.md                        you are here
│
├── # Baseline scaffold (always copied)
├── package.json                     pinned deps; React 18 + jdm-editor + copilotkit
├── vite.config.ts                   wasm plugin + dev proxies for :4100/:4242/:8090
├── tsconfig.{json, app.json, node.json}
├── eslint.config.js                 flat config, react-hooks + react-refresh
├── index.html                       __TITLE__ → <title>
├── favicon.svg                      generic atomic-fi mark
├── main.tsx                         React 18 createRoot boot
├── index.css                        Tailwind v4 @theme + shadcn vars (zinc/new-york)
│
├── lib/
│   ├── utils.ts                     `cn()` helper
│   ├── session.ts                   bearer storage + login() against POST /api/sessions
│   ├── api-client.ts                api.ts seed — bearer-mode authHeaders + request<T>
│   ├── copilot.ts                   resolves runtimeUrl (env var or /api/copilotkit)
│   ├── rules-api.ts                 CRUD against /api/rules/<type>/<name>
│   ├── zenrule.ts                   POST /api/projects/<type>/evaluate/<name> (simulator)
│   └── lotus.ts                     bearer → getEmbedToken() → embedUrl()
│
├── components/
│   ├── login-gate.tsx               boot gate, email+password+tenant
│   ├── copilot-provider.tsx         <CopilotKit> wrapper
│   ├── jdm-editor-panel.tsx         <DecisionGraph> wired to rules-api
│   ├── lotus-panel.tsx              <iframe title="Lotus Dashboard" />
│   └── app-shell.tsx                three-tab chrome (Demo / Rule / Audit)
│
└── components-ui/                   shadcn primitives, inlined
    ├── button.tsx
    ├── card.tsx
    ├── input.tsx
    ├── label.tsx
    └── tabs.tsx
```

## Substitutions

| Placeholder           | Replaced with                                       | Files affected                                           |
|-----------------------|-----------------------------------------------------|----------------------------------------------------------|
| `__SLUG__`            | kebab-case slug (e.g. `payments-console`)           | `package.json`, `vite.config.ts`, `lib/session.ts`       |
| `__TITLE__`           | human-readable title (e.g. `"Payments Console"`)    | `index.html`, used in agent-generated `App.tsx` header   |
| `__APP_DESCRIPTION__` | one-line use-case summary shown in LoginGate         | `components/login-gate.tsx`                              |

## Dev-mode wiring

The generated `vite.config.ts` proxies in dev so relative URLs work whether the
app is served by Phoenix (production) or by vite directly:

```
/api/copilotkit/*  →  http://localhost:4242   (copilot-runtime host port)
/api/projects/*    →  http://localhost:8090   (ZenRule)
/api/*             →  http://localhost:4100   (Phoenix)
```

In Phoenix-served prod (`/demo/<slug>/`), same-origin handles `/api/*` natively;
`/api/copilotkit` and `/api/projects` need a Phoenix-side proxy (not currently
wired in this repo). For dev-on-vite, the proxies above are what makes it work
without env vars.

Override paths via env (per-app `.env.local`):

| Env var                      | Default                  | Purpose                          |
|------------------------------|--------------------------|----------------------------------|
| `VITE_COPILOT_RUNTIME_URL`   | `/api/copilotkit`        | Point at a remote runtime        |
| `VITE_ZENRULE_URL`           | `` (same-origin / proxy) | Point at a remote ZenRule        |

## What is NOT here (intentionally)

- `tailwind.config.ts` — Tailwind v4 reads `@theme` from `index.css`.
- `App.tsx` — generated per use case from the pattern in the agent doc.
- `useHumanInTheLoop()` tool definitions — the editor (`atomic-fi-jdm-editor/`)
  registers save_rule / add_node / simulate_rule / etc. via CopilotKit's v2 HITL
  API; generated demo apps don't need that complexity by default. If a use case
  calls for a CopilotKit-powered Demo tab, add tool registrations ad-hoc.
- `axios`, `antd`, `react-ace`, `graphology` — heavy deps the full editor needs.
  Demo apps embed `<DecisionGraph>` directly and use vanilla `fetch`.
- `.env*` files — credentials live in sessionStorage; the only env vars are the
  optional override URLs above, documented in the README the agent generates.

## Why pin versions here

Generated apps must build today and tomorrow. Floating semver ranges across N
demo apps would mean random breakages when a downstream dep ships a bad minor —
and a CopilotKit minor bump would silently desync the AG-UI wire protocol.
Pin once here, audit when bumping, and every generated app inherits the same
known-good set.
