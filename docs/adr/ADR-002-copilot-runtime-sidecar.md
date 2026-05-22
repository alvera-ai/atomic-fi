# ADR-002: Copilot runtime — generic dockerized CopilotKit sidecar, v2 Factory Mode

**Status:** Proposed
**Date:** 2026-05-22
**Deciders:** atomic-fi maintainers (himangshu, + reviewers)
**Relates to:** [ADR-001](./ADR-001-one-command-local-dev.md) (one-command local dev)

## Context

GH-49 added a CopilotKit copilot to the JDM editor. The first cut reimplemented
the CopilotKit GraphQL runtime in Elixir (`AtomicFi.CopilotKitContext` +
`Incremental`). It is server-correct, but the browser renders nothing — the
Elixir `multipart/mixed` incremental-delivery encoding is not parsed by the
CopilotKit React client (BLOCKER 2). CopilotKit ships `@copilotkit/runtime` as
library middleware — not a server, and not an official image (verified: no
`copilotkit/runtime` image exists; `copilotkithq/` publishes only `guardrails`).
A matched client/runtime pair is the only reliably-rendering combination.

ADR-001's target state absorbs both LLM sidecars into Phoenix as Elixir (no Node
sidecar). That end-state is not abandoned — it is deferred: the Elixir copilot
cannot render today, and blocking GH-49 on a from-scratch GraphQL-incremental
encoder is not justified.

## Decision

1. **A generic `copilot-runtime` is (re)introduced as a dockerized backing
   service** — `external-deps/copilot-runtime/`, parallel to ZenRule and
   Watchman, started by `make run-backing-services`. It is *generic*: a
   CopilotKit proxy with zero JDM/domain logic. The JDM authoring prompt and
   the 11 copilot actions stay in the editor (`atomic-fi-jdm-editor`).
2. **v2 Factory Mode** — `@copilotkit/runtime/v2`, `BuiltInAgent`,
   `createCopilotHonoHandler`; AG-UI native, env-switchable model provider.
3. **Toolchain: bun.** **LLM SDK: the Vercel AI SDK** (`"aisdk"` factory
   variant) — see below.
4. **The Elixir `/api/copilotkit` (`CopilotKitController` + `CopilotKitContext`
   + `Incremental` + tests) is kept, dormant and unwired.** ADR-001's
   Elixir-absorption end-state is rewired in when the ZenRule + Watchman Docker
   services are themselves retired.

## SDK choice — Vercel AI SDK now, TanStack AI later (deferred call)

The runtime's LLM SDK was weighed as Vercel AI SDK vs TanStack AI:

- **Taste / type-purism** points at TanStack AI — consistent with
  bun-over-pnpm, elixir-over-express, and the `ts-pattern` + `zod`/`valibot`
  house style.
- **Integration grain** points at the Vercel AI SDK: CopilotKit itself is built
  on it (`@copilotkit/runtime` depends on `ai`); `BuiltInAgent`, `resolveModel`,
  the `convert*ToVercelAISDK*` helpers and the `"aisdk"` factory variant are
  first-class. TanStack AI is the secondary `"tanstack"` variant on a much
  younger library.

**Decision: Vercel AI SDK for now** — the standard supported path while the
runtime is vendored *inside* CopilotKit's framework. Same call as the
`@hey-api` generated SDK: take the default/supported path where we are a guest
in someone else's tooling.

**Revisit (deferred):** re-evaluate in a few months. **When `copilot-runtime`
is brought fully in-house** — owned end to end, blast radius controlled —
**adopt TanStack AI as the gold standard.** The taste pick lands where we
control the stack (as bun and Elixir did). Recorded here so it is tracked, not
forgotten.

## Consequences

- GH-49's copilot renders via the matched CopilotKit client/runtime pair.
- One more Docker backing service for local dev — consistent with ADR-001 C4
  (Docker confined to required backing services).
- Two copilot backends exist transiently: the live Node `copilot-runtime` and
  the dormant Elixir endpoint. Accepted as transitional; convergence to one is
  gated on the Watchman/ZenRule Docker retirement.
- A future SDK migration (Vercel AI SDK → TanStack AI) is expected and
  pre-recorded, not a surprise.
