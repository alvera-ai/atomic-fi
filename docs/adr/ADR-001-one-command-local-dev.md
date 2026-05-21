# ADR-001: One-command local dev — Phoenix-centric stack, native, Ollama

**Status:** Proposed
**Date:** 2026-05-20
**Deciders:** atomic-fi maintainers (himangshu, aniket, + reviewers)
**Revision:** 3 — consolidates the feasibility deep-dives (document-agent,
jdm-copilot-runtime, Lotus AI, Elixir LLM/JDM ecosystem).

## Context

Running atomic-fi locally is an 8-process, 6-runner, 3-LLM-provider ritual
with no single entry point. The goal is **one `make run`** and a stack
simple enough to reason about.

### What exists today

```
  Browser
   ├─▶ atomic-fi-web        :5173 ┐
   ├─▶ atomic-fi-jdm-editor :5173 ┼─ 3 SPAs, same port (collision)
   ├─▶ lotus-embed          :5173 ┘
   └─▶ onboarding-flow      :8080
            │  │  │
            │  │  └─▶ document-agent :8100  (Python/uv)  ─▶ Gemini API       ☁
            │  └────▶ jdm-copilot    :4111  (Node/tsx)   ─▶ OpenAI/Anthropic  ☁
            └───────▶ Phoenix        :4100  (Elixir, native)
                          ├─▶ ZenRule  :8090  (docker)
                          └─▶ Watchman :8084  (docker)

  8 native processes · runners: iex·uv·tsx·pnpm·npm·bun · 3 LLM providers · 3 secrets
```

Pain points: no single entry command; runner sprawl (`onboarding-flow` ships
*both* a `bun.lockb` and a `package-lock.json`; `lotus-embed` is missing from
`pnpm-workspace.yaml`); three SPAs collide on port 5173; one live
`GOOGLE_API_KEY` hand-copied across three git-ignored files; the copilot
runtime lives only in the detached, prunable `atomic-fi-jdm` worktree against
an older schema; `make sight` points at a non-existent
`packages/atomic-sight-insight`.

### Constraints

- **C1** Elixir runs natively — no containerized Phoenix. (Already true.)
- **C2** Ollama replaces Gemini and OpenAI/Anthropic for local dev — no
  cloud LLM keys required to run the stack.
- **C3** The CopilotKit UI talks to the atomic-fi server over HTTP.
- **C4** `make run` itself never invokes Docker. Docker is confined to the
  two backing services, which are **required** (not optional) and started
  by a separate, documented `make run-backing-services` step.

## Decision

Collapse the stack to a **Phoenix-centric** topology. Phoenix becomes the
only application backend and the only origin the browser talks to. The React
apps fold into one SPA. **Both LLM sidecars are absorbed into Phoenix as
Elixir** — there is no Python service and no Node sidecar in the target
state. ZenRule and Watchman stay as Docker backing services for this
iteration.

```
  Browser
   └─▶ atomic-fi-web   ONE SPA   routes: /  /onboarding  /jdm  /lotus
            │
            ▼   single origin, all HTTP
   ┌──────────────────────────────────────────────────────┐
   │  Phoenix  :4100   (Elixir — the only app backend)     │
   │                                                        │
   │   GET /              → built SPA assets (Plug.Static)  │
   │   /api/rules…        → REST                            │
   │   /api/screening…    → REST ───────────┐               │
   │   /api/parse         → document parser ┤ Instructor    │
   │   /api/copilot       → copilot runtime ┤ ReqLLM        │
   │        │      │                        ▼               │
   │        │      │                 Ollama :11434 (native, │
   │        │      │                 or cloud via config)   │
   │        ▼      ▼                                        │
   │   ZenRule    Watchman    (Docker backing services —     │
   │   :8090      :8084/:9094  REQUIRED; started by          │
   │                           `make run-backing-services`)  │
   └──────────────────────────────────────────────────────┘

  make run               → native: Phoenix + Vite (HMR); preflights Ollama
  make run-backing-services → Docker Compose: ZenRule + Watchman (prerequisite)
```

### Target process/port map

| Process | Port | How it runs |
|---|---|---|
| Ollama daemon | 11434 | native install; `make run` preflights it |
| Phoenix (API + SPA + parser + copilot) | 4100 | native — `make run` |
| Vite dev server (HMR only, dev) | 5173 | native — `make run` |
| ZenRule | 8090 | **Docker** — `make run-backing-services` |
| Watchman | 8084 / 9094 | **Docker** — `make run-backing-services` |

Native process count drops from 8 to 2 (Phoenix + Vite; Ollama is a daemon
you already run). The triple `:5173` collision is gone — one SPA, one Vite.
The Python `uv` runner and the Node `tsx` sidecar leave the runtime
entirely; Node survives only as a dev-time Vite build tool.

## Decision 1 — Document parser: Instructor + Ollama, inside Phoenix

The Python `document-agent-server` is replaced by an Elixir module behind
`POST /api/parse`. Code reading confirmed it has **no protocol** — it is
request → model call → JSON — so the port is mechanical. The substance:

**Structured output → `instructor_ex`.** The six Pydantic models in
`app/schemas.py` (`IdentityDocument`, `BankStatement` with nested
`list[Transaction]`, `MemorandumOfAssociation`, …) become six Ecto embedded
schemas. Instructor is the idiomatic fit: `@llm_doc` describes the schema to
the model, `validate_changeset/1` adds *semantic* validation, and
`max_retries` re-prompts on invalid output — strictly better than Gemini's
shape-only `response_schema`. Instructor's README confirms first-class
Ollama support.

**Verified caveat — Instructor's multimodal input is undocumented.**
Instructor's `messages` are text-shaped in every example; image input is not
a documented feature. The parser is therefore designed in **two stages**:

1. *Vision call* — rasterized page image(s) → model. The transport must
   carry images, so this stage uses **ReqLLM** (`ContentPart.file/image`,
   confirmed multimodal) or the raw `ollama` client's `images` field. PDFs
   are rasterized first with **poppler** (`pdftoppm`); text-dense docs
   (statements, memoranda) can instead use the `pdftotext` text layer.
2. *Structure + validate* — Instructor coerces the extracted content into
   the Ecto schema with changeset validation and retry.

A short spike can confirm whether Instructor's Ollama adapter forwards a
multimodal content array; if it does, the two stages collapse to one. The
design does not depend on that.

**Provider is config, not code.** Local dev → `ollama:` (with the poppler
rasterize step). A PDF-native cloud model (`google:`, `anthropic:`,
`openai:` — all ingest PDFs directly, no rasterization) is a model-string
swap, because the underlying client is provider-agnostic. C2 is satisfied
by the default; quality escalation is one config line.

**Residual risk:** local vision/text models will not match Gemini on dense
multi-page documents. `tests/test_extract.py` is the gate; the quality delta
must be measured, and it is a risk C2 forces regardless of language.

## Decision 2 — Copilot runtime: Elixir, modeled on `Lotus.AI`

The Node `jdm-copilot-runtime` is replaced by an Elixir copilot runtime
inside Phoenix behind `POST /api/copilot`. Code reading settled the shape:

- The Node sidecar's *own* code is ~3 files of glue; the substance was
  `@copilotkit/runtime` (a GraphQL-Yoga server) — not REST.
- `runtime.ts` openly depends on **undocumented CopilotKit internals**
  ("the `Message` class isn't exported"; mutating `inputMessages` "is the
  supported way in @1.10.5"). Reimplementing *that protocol* in Elixir would
  chase the same internals — rejected.

**What we build instead, and what it's modeled on.** `Lotus.AI` (already a
dependency, in `deps/lotus`) is a working, in-repo template for exactly this
job, and it is built on **ReqLLM**:

- `Lotus.AI` — a config-driven model facade (`config :lotus, ai: [model:,
  api_key:]`, `{:system, ENV}` resolution, `{:ok, _}/{:error, atom}` tuples).
- `Lotus.AI.Action` — a behaviour for tools (`name/0`, `description/0`,
  `schema/0` in NimbleOptions form, `run/2`).
- `Lotus.AI.Tool.run/4` — **a complete recursive tool-calling loop**:
  `ReqLLM.generate_text(model, msgs, tools:)` → classify → on `:tool_calls`,
  `execute_and_append_tools` → recurse to `max_iterations`.
- `Lotus.AI.Conversation` — multi-turn history, context-message building,
  pruning, auto-retry-on-error — directly reusable for chat state.

So `AtomicFiWeb.Copilot` is patterned on `Lotus.AI` + `Lotus.AI.Tool`, sharing
the same ReqLLM spine and (optionally) the same `:ai` config block.

**Don't restrict to Lotus — the wider Elixir survey.** Lotus is the *minimal*
in-repo version of this pattern. The ecosystem also has:

| Option | Shape | Fit here |
|---|---|---|
| `Lotus.AI.Tool` | ~150 LOC, in `deps/` already, ReqLLM | **Right-sized** for one runtime |
| Jido + Jido.AI | Full agent framework — agents as supervised processes, ReAct/CoT, multi-agent; *same authors as ReqLLM* | Overkill now; the scale-up path if atomic-fi grows more agentic surfaces |
| LangChain (Elixir) | `LLMChain` + tool calling | Viable; heavier dep, different idiom |
| AshAI | Structured output + tools + MCP, for Ash apps | Only if atomic-fi adopts Ash |

There is **no Elixir "CopilotKit runtime" equivalent** — every Elixir agent
framework does *server-side* tool calling; CopilotKit's distinguishing
feature is *browser-defined* tools. Recommendation: model on `Lotus.AI.Tool`
now (smallest correct machinery, already vendored), keep Jido in mind as the
growth path.

**The one genuine wrinkle — server-side vs browser-side tools.**
`Lotus.AI.Tool.run/4` executes tools *server-side* (its callback runs
`action_module.run/2` in-process). The JDM copilot's tools split:

- *Server-natured* — `save_rule`, `simulate_rule` (→ ZenRule), listing rules.
  These become `Lotus.AI.Action`-style modules and run server-side directly.
  This also satisfies **C3** — they are real atomic-fi HTTP/Action calls.
- *Canvas-bound* — `add_node` and graph mutations must run in the browser.
  For these the loop needs a step Lotus's version lacks: emit the tool call
  to the browser (Phoenix Channel/SSE), pause, resume on the posted-back
  result.

So `AtomicFiWeb.Copilot` = `Lotus.AI.Tool.run` extended with a "client tool"
branch. The editor's `src/copilot/` drops `@copilotkit/runtime`'s client and
hits `/api/copilot`; its preview-card UX is preserved.

## Decision 3 — Backing services: Docker Compose, this iteration

Watchman (sanctions screening) and ZenRule (the JDM rules engine) are
**required** runtime dependencies, kept exactly as they are — Docker
Compose, started by `make run-backing-services`. Native interop was
evaluated and **deferred** as not worth the lift now:

- **ZenRule → embed (future).** GoRules Zen Engine has a Rust core; the
  clean path is a **Rustler NIF over the `zen-engine` crate** — the
  `duckdbex`-style pattern, JDM eval being a fast pure function. Note: the
  `@gorules/zen-engine-wasm` npm package is wasm-bindgen + JS glue, so it
  will *not* drop into `Wasmex` cleanly; a Wasmex route would need a custom
  `wasm32-wasi` build, making Rustler the simpler native option. There is
  **no native Elixir JDM library** (`rules_engine` on hex is an EasyRules
  port — a different paradigm).
- **Watchman → supervise (future).** Watchman is a Go *service* with
  background list-refresh and large in-memory indices — it does not embed as
  a NIF in any language. The right BEAM pattern is a **supervised OS Port**
  (the Go binary as an OTP-tree child) — no Docker, but still a process.

Both are tracked for a future ADR; neither blocks `make run`.

## Consequences

### Easier

- One command for the native stack; one origin for the browser.
- No cloud LLM keys to run locally; the `GOOGLE_API_KEY` references are
  removed (the key was never committed — git-ignored — so this is cleanup,
  not leak remediation).
- One SPA, one Vite build — the `:5173` collision is gone.
- Python and the Node sidecar leave the runtime; ReqLLM is the single LLM
  spine (Lotus already uses it), Instructor the single extraction layer.
- The copilot integration tracks live schema instead of a detached worktree.

### Harder / taken on

- **Document extraction quality must be re-benchmarked** on local models;
  `tests/test_extract.py` is the gate. Unavoidable under C2.
- **New native dep: poppler** (`pdftoppm`/`pdftotext`); `tesseract` if
  scanned-PDF OCR is needed.
- **Instructor multimodal spike** — confirm or fall back to the two-stage
  design.
- **The copilot client round-trip** for canvas-bound tools is new code, and
  the editor's `src/copilot/` is reworked off `@copilotkit/runtime`.
- **First-run `ollama pull`** of a chat model and a vision model is
  multi-GB; `make run` must detect and instruct.
- SPA consolidation needs React-version reconciliation (jdm-editor: React 18
  + antd + wasm plugin; others React 19).

### To revisit (future ADRs)

- ZenRule embed (Rustler NIF) / Watchman supervise (OS Port).
- A CI smoke test booting the stack and health-checking every port.
- Pruning the `atomic-fi-jdm` worktree post-consolidation.

## Action Items

1. [ ] Land this ADR under `docs/adr/`.
2. [ ] Remove the now-unused `GOOGLE_API_KEY` references from
   `example-apps/document-agent-server/.env`, `config/dev.secret.exs`,
   `atomif-fi-dev.secret.exs` (all git-ignored — never committed; the
   Ollama default needs no key).
3. [ ] Consolidate the four React apps into `atomic-fi-web` as routes; one
   Vite build served via `Plug.Static`; remove dead `make sight`.
4. [ ] **Decision 1** — `AtomicFi.DocumentParser` + `POST /api/parse`: six
   Ecto embedded schemas, Instructor for structure/validation, ReqLLM (or
   `ollama` client) for the vision call, poppler rasterization,
   `Task.async_stream` concurrency. Spike Instructor multimodal. Re-run
   `tests/test_extract.py`; record the quality delta. Retire
   `document-agent-server`.
5. [ ] **Decision 2** — `AtomicFiWeb.Copilot` + `POST /api/copilot`,
   modeled on `Lotus.AI`/`Lotus.AI.Tool`: server-side `Action` tools for
   `save_rule`/`simulate_rule`/listing; client round-trip branch for
   canvas-bound tools; rework the editor's `src/copilot/` off
   `@copilotkit/runtime`. Retire `jdm-copilot-runtime` and the worktree.
6. [ ] Point Lotus AI (`config/dev.secret.exs`) at Ollama.
7. [ ] Single root `.env`; drop `onboarding-flow`'s `bun.lockb`; add
   `lotus-embed` to `pnpm-workspace.yaml`.
8. [ ] Author the root `Procfile` + `make run` (Ollama preflight, Phoenix,
   Vite); document `make run-backing-services` as a prerequisite in `README`.
9. [ ] CI smoke test: boot the stack, health-check every port.

## Appendix — proposed `Procfile` and `make run`

```Procfile
# Native only. ZenRule + Watchman are required backing services started
# separately via `make run-backing-services` (Docker Compose).
phoenix:  iex -S mix phx.server
web:      cd atomic-fi-web && pnpm dev          # Vite HMR; proxies /api -> :4100
```

```makefile
run:
	@command -v ollama >/dev/null || { echo "✗ ollama not installed — https://ollama.com"; exit 1; }
	@curl -sf http://localhost:11434/api/tags >/dev/null \
		|| { echo "✗ ollama daemon not running — start 'ollama serve'"; exit 1; }
	@curl -sf http://localhost:8090/health >/dev/null \
		|| echo "⚠ ZenRule not up — run 'make run-backing-services' first"
	@command -v overmind >/dev/null && exec overmind start -f Procfile || exec hivemind Procfile
```
