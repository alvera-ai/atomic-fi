# PRD — atomic-fi: single-app demo build

**Status:** Draft
**Owner:** himangshu (hh@v3.cash)
**Repo:** alvera-ai/atomic-fi
**Date:** 2026-05-20

---

## Summary

Collapse atomic-fi local dev into one Phoenix app. Phoenix serves the REST
API, the document parser, and the example apps. The Python document-agent is
folded into Elixir. The copilot runtime keeps its idiomatic CopilotKit (Node)
shape but is repointed at local Ollama. One `make server` runs it, one Ollama
daemon backs both AI features, no cloud LLM keys. Watchman and ZenRule stay as
Docker backing services.

The line in the sand: **the demo build runs on one machine with `make server`
+ local Ollama, no API keys.**

## Problem

Running atomic-fi locally takes 8 native processes across 6 runtimes (`iex`,
`uv`, `tsx`, `pnpm`, `npm`, `bun`), 3 LLM providers, and 3 hand-copied
secrets — with no single command. Three example SPAs collide on `:5173`,
`make sight` points at a directory that no longer exists, and the copilot
runtime lives in a detached, prunable git worktree built against an old
schema. New contributors can't stand the stack up, and demos are fragile.

## Goals

- **One command.** `make server` runs the whole app; `make run-backing-services`
  (once) starts the Docker services.
- **No cloud LLM keys.** Both AI features run against local Ollama.
  Demo-grade by design (see Non-Goals).
- **The Python service is gone.** The document parser becomes an Elixir
  module in Phoenix.
- **Copilot stays idiomatic, off cloud.** The CopilotKit runtime keeps its
  shape; only its LLM backend changes to Ollama, and it moves out of the
  worktree into the repo.
- **One origin.** Phoenix serves the example apps; the browser hits one host.

## Non-Goals

- **Native interop for Watchman / ZenRule.** They stay Docker backing
  services. Embedding them is deferred to its own ADR.
- **Rewriting the copilot UI or the AI streaming round-trip.** Both are
  fixed. Only the runtime's LLM backend changes.
- **Reimplementing the CopilotKit runtime in Elixir.** The idiomatic runtime
  is the Node `@copilotkit/runtime`; it stays.
- **Folding the example apps into one SPA.** Each stays an independent,
  self-contained static build.
- **Production-grade extraction accuracy.** This is the demo build; local
  models are accepted. Production deployments switch the provider via config.

## Users

| Persona | Need |
|---|---|
| atomic-fi developer | one command to run the full app |
| new contributor | clone → running stack, no tribal knowledge |
| demo-giver | every example reachable from one index page |

## User Stories

**As a developer, I want** `make server` to run Phoenix and rebuild the
example apps **so that** I don't manage 8 terminals.

**As a developer, I want** the document parser and copilot to work with no
API key **so that** a missing secret never blocks local work.

**As a new contributor, I want** to reach a running stack from a clean clone
by following the README **so that** I don't need tribal knowledge.

**As a demo-giver, I want** one `/demo` index page linking every example app
**so that** I can walk a customer through them without juggling dev servers.

## Models

Two Ollama models, pulled locally; no cloud key. The reasoning model is a
qwen/gemma-family model — already validated to work well in this stack.

| Model | Used by |
|---|---|
| Vision model | `/api/parse` — reads rasterized document pages |
| Reasoning model (qwen / gemma) | copilot runtime · Lotus AI SQL generation · JSON-structured extraction |

## Requirements — P0 (entire v1)

### P0-1 — Example apps served by Phoenix under `/demo`

Each example app (`onboarding-flow`, `atomic-fi-jdm-editor`, `lotus-embed`)
is an independent, self-contained static build (HTML/JS/CSS). Phoenix serves
them; a controller-rendered index page links them.

- [ ] Each app's `vite.config.ts` sets `base: "/demo/<app>/"` and
  `build.outDir` → `priv/static/demo/<app>`.
- [ ] `plug Plug.Static, at: "/demo"` serves `priv/static/demo`.
- [ ] A controller action renders the `/demo` index page — a list of links,
  one per example app.
- [ ] No deep-linking between examples; each loads at its own root. No SPA
  fallback routes.
- [ ] Per-app build output is git-ignored.

### P0-2 — `make server` runs the example-app builds

**Current state.** `config/dev.exs` runs only `esbuild` + `tailwind`
watchers (Phoenix's own `assets/`). `make server` = `iex -S mix phx.server`
starts Phoenix + those two. The example apps have no Phoenix integration —
they run separately via their own `pnpm`/`npm`/`bun` dev servers. `make sight`
points at the nonexistent `packages/atomic-sight-insight`. `make up` tells
you to run things "in separate terminals."

**Replacement.**

- [ ] Add one `vite build --watch` watcher per example app to the
  `watchers:` list in `config/dev.exs` — `make server` rebuilds them on change.
- [ ] Add `~r"priv/static/demo/.*"` to the `live_reload` patterns so a
  rebuilt example refreshes the browser.
- [ ] Remove the dead `make sight` target; fix the `make up` message.
- [ ] `make server` is unchanged as a target — it gains the example builds
  transitively via `dev.exs`.

### P0-3 — Document parser as an Elixir module (`POST /api/parse`)

Replaces the Python `document-agent-server`.

- [ ] `AtomicFi.DocumentParser` accepts the same multipart contract
  (`files[]` + `metadata[]`).
- [ ] PDFs rasterized via poppler (`pdftoppm`).
- [ ] Extraction uses Instructor + the Ollama vision model — six Ecto
  embedded schemas (ex-Pydantic), `validate_changeset/1`, `max_retries`.
- [ ] Implementation note: if Instructor's Ollama adapter does not forward a
  per-message `images:` field, the vision call uses the raw `ollama` client;
  Instructor still does validation.
- [ ] `document-agent-server` is removed.

### P0-4 — Copilot runtime repointed at Ollama

The CopilotKit UI and the AI streaming round-trip are fixed. Only the
runtime's LLM backend changes — the idiomatic CopilotKit move.

- [ ] `jdm-copilot-runtime` is moved out of the `atomic-fi-jdm` worktree into
  the main repo (`example-apps/`), tracking current schema; the worktree is
  pruned.
- [ ] Its LLM adapter is swapped from OpenAI/Anthropic to Ollama —
  CopilotKit's `OpenAIAdapter` pointed at Ollama's OpenAI-compatible
  endpoint, using the reasoning model.
- [ ] The editor's `src/copilot/` UI is unchanged. The CopilotKit runtime
  protocol / streaming round-trip is unchanged.
- [ ] The runtime is started by `make server` as a Phoenix `watchers:` entry
  (a long-running process, like the esbuild watcher).
- [ ] No OpenAI/Anthropic key is required.

### P0-5 — Backing services + Ollama config

- [ ] `make run-backing-services` starts ZenRule + Watchman via Docker
  Compose; documented in the README as a prerequisite. `make server` never
  invokes Docker.
- [ ] Both Ollama models (vision, reasoning) are documented as a one-time
  `ollama pull`.
- [ ] Lotus AI (`config/dev.secret.exs`) points at the Ollama reasoning model.
- [ ] The unused `GOOGLE_API_KEY` references are removed from the three
  git-ignored files that carry them (the key was never committed).

## Acceptance Criteria

**Example apps**
- Given `make server` is running, when I open `/demo`, then I see a page
  linking every example app, and each link opens that app.
- Given I edit an example app's source, when its watcher rebuilds, then the
  browser reloads with the change.

**Document parser**
- Given a PDF or image posted to `/api/parse`, when extraction runs, then the
  response is structured JSON matching the document's Ecto schema.
- Given no `GOOGLE_API_KEY` is set, when `/api/parse` is called, then it
  still works (local Ollama).

**Copilot**
- Given the editor's copilot panel, when I send a message, then it streams a
  response via the CopilotKit runtime backed by Ollama — no OpenAI/Anthropic
  key set.
- Given the runtime, then it lives in the main repo, not the `atomic-fi-jdm`
  worktree.

**Run**
- Given a clean clone, when I run `make run-backing-services` then
  `make server`, then Phoenix, the example apps, the copilot runtime, and
  both AI endpoints are up — no other command.

## Scope of v1

Single ship. All P0 items land together. The build is demo-grade: one
machine, `make server` + local Ollama, no API keys. Production deployment
(single app, provider switched via config) is a follow-on, not part of this
PRD.

## Risks

| Risk | Mitigation |
|---|---|
| Instructor's Ollama adapter doesn't forward images | Fall back to the raw `ollama` client for the vision call — known, low-risk |
| Local-model extraction weaker than Gemini | Accepted — demo build; production switches provider via config |
| Example-app builds slow `make server` startup | `vite build --watch` is incremental; only the first build is slow |
