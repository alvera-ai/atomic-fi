---
name: vitest-to-react
description: PLACEHOLDER — future agent. Will read a vitest integration spec and its recorded request/response artifacts and emit an interactive React demo component for an `atomicfi-example-web` reference app (modeled on https://www.furever.dev/). Not implemented yet — invoking this agent today will report "not implemented" and exit.
tools:
  - Read
  - Write
---

# vitest-to-react — PLACEHOLDER

This agent is not implemented yet. Today, invoking it should:

1. Print: `vitest-to-react is a placeholder; not implemented yet. See .claude/agents/vitest-to-react.md.`
2. Exit cleanly without writing any files.

## Future scope (when this gets fleshed out)

**Reference:** https://www.furever.dev/ — the visual / interaction model for the demo app. A clean, opinionated, single-page reference UX that walks a developer through a real-world flow against the live API. The atomic-fi equivalent lives at `atomicfi-example-web/` in this repo.

**Inputs** (same shape as `vitest-to-mdx` and `vitest-to-bruno`):
- `integration-tests/tests/cookbook/<slug>.test.ts`
- `integration-tests/recordings/<slug>/*.jsonl`

**Output** (target — to be confirmed at implementation time):
- One page or panel per use-case under `atomicfi-example-web/src/pages/cookbook/<slug>/` (or component layout TBD)
- Each step from the recordings becomes an interactive UI affordance: form inputs mirroring the request body, a "Run step" button that fires the real API call, response panel showing live data
- The whole app reads as a "live cookbook" the way furever.dev reads as a live Stripe demo
- MDX integration (when this agent ships): `vitest-to-mdx` gains a Tabs block alongside the curl/response code blocks with a `<TabItem value="demo">` that links to the corresponding `atomicfi-example-web` page

**Open questions to resolve at implementation time:**
1. Does `atomicfi-example-web/` ship in this repo or in a sibling repo? furever.dev is its own repo — there's a case for keeping the example app separate so it can iterate without touching the platform.
2. Does the React component fire requests against the real Phoenix server (CORS! local-dev only?) or against a mocked recording-replay layer for production-deploy demo mode?
3. Auth UX — bring-your-own API key in localStorage (stripe-keys-style) or piggy-back on a session cookie?
4. Form schema — generate from the OpenAPI spec (single source of truth), or just copy whatever shape the recording has? furever.dev derives forms from the Stripe API; we should likely do the same with our OpenAPI spec.
5. Styling — Tailwind + shadcn (matches furever.dev's clean look) or pick something else?

**Until implementation:** the parent skill (`usecase-vitest`) MUST NOT spawn this agent automatically. Only spawn it when the human explicitly asks. Default fan-out is `vitest-to-mdx` + `vitest-to-bruno` only.

---

## Stub behavior (current)

When invoked today, write nothing and return:

```
vitest-to-react: not implemented yet.

Inputs found:
- integration-tests/tests/cookbook/<slug>.test.ts (exists | missing)
- integration-tests/recordings/<slug>/   (N files | none)

Reference design: https://www.furever.dev/
Target output dir (TBD): atomicfi-example-web/

To implement: see .claude/agents/vitest-to-react.md "Future scope" section.
```

That is the entire behavior of this agent today. It exists so the toolchain has a slot for the React generator and the README can document the full pipeline.
