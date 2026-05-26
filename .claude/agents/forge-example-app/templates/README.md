# `forge-example-app` templates

Copy-paste sources used by the `forge-example-app` agent. The agent reads these,
substitutes `__SLUG__` / `__TITLE__` / `__APP_DESCRIPTION__` → real values, and
drops them into `example-apps/<slug>/`. Edit here when the baseline stack or
auth pattern moves; the agent picks up the changes on its next run.

The agent is **self-sufficient**: a generated app builds even if
`example-apps/lotus-embed/` (or the entire `example-apps/` dir) is missing.
Existing apps are cross-references, not dependencies.

## Layout

```
templates/
├── README.md                        you are here
│
├── # Baseline scaffold (always copied)
├── package.json                     pinned deps; React 19 + Vite + Tailwind v4 + shadcn
├── vite.config.ts                   __SLUG__ → base + outDir
├── tsconfig.json                    references composite
├── tsconfig.app.json                src/ compile (with @/* path alias)
├── tsconfig.node.json               vite.config.ts compile
├── eslint.config.js                 flat config, react-hooks + react-refresh
├── index.html                       __TITLE__ → <title>
├── favicon.svg                      generic atomic-fi mark
├── main.tsx                         React 19 createRoot boot
├── index.css                        Tailwind v4 @theme block + shadcn vars (zinc/new-york)
├── lib/
│   ├── utils.ts                     `cn()` helper
│   └── api-client.ts                api.ts seed — bearer-mode authHeaders + request<T>
└── components-ui/                   shadcn primitives, inlined (no registry fetch at runtime)
    ├── button.tsx
    ├── card.tsx
    ├── input.tsx
    └── label.tsx
│
├── # Auth + Lotus (mandatory in every generated app)
├── lib/session.ts                   sessionStorage get/set + login() against POST /api/sessions
├── components/login-gate.tsx        email + password + tenant form, pre-filled with dev creds
├── lib/lotus.ts                     bearer → getEmbedToken() → embedUrl()
└── components/lotus-panel.tsx       <LotusPanel bearer={…} /> renders the iframe
```

Every scaffolded app runs the same boot dance:

```
1. App() reads getStoredBearer().
2. No bearer → render <LoginGate onConnected={setBearer} />, return early.
3. Bearer present → render the use-case flow + <LotusPanel bearer={bearer} />.
```

This is the same pattern `lotus-embed` uses, just split into reusable components
so each new app inherits it without duplicating the state machine.

## What is NOT here (intentionally)

- `tailwind.config.ts` — Tailwind v4 reads config from `@theme` inside CSS
  (`index.css`), so no separate config file is needed.
- `App.tsx` — generated per use case, no template.
- The api-key / `ConnectGate` flow (used by `onboarding-flow` and
  `atomic-fi-jdm-editor`). Generated apps always embed Lotus, and
  `POST /api/lotus/embed-token` requires a human session, so the api-key path
  isn't a fit. If a future demo legitimately needs api-key auth, branch a sibling
  agent rather than re-introducing the auth fork here.
- Additional shadcn primitives (dialog, table, badge, …) — added only when the
  use case actually needs them. Agent pulls canonical implementations from the
  shadcn/ui `new-york` style at generation time.
- `.env*` files — credentials live in sessionStorage, not env vars.

## Substitutions

| Placeholder           | Replaced with                                                 | Files affected                                    |
|-----------------------|---------------------------------------------------------------|---------------------------------------------------|
| `__SLUG__`            | kebab-case slug (e.g. `kyc-gate-demo`)                        | `package.json`, `vite.config.ts`, `lib/session.ts` |
| `__TITLE__`           | human-readable title (e.g. `"KYC Gate Demo"`)                 | `index.html`                                      |
| `__APP_DESCRIPTION__` | one-line use-case summary shown in the LoginGate              | `components/login-gate.tsx`                       |

## Why pin versions here

Generated apps must build today and tomorrow. Floating semver ranges across N
demo apps would mean random breakages when a downstream dep ships a bad minor.
Pin once here, audit when bumping, and every generated app inherits the same
known-good set.
