# atomic-fi — Local Dev Architecture

Pictures first. Words are captions. Rationale + options live in
`docs/adr/ADR-001-one-command-local-dev.md`.

---

## 1. Topology (C4 context)

```
                       ┌────────────────────────┐
                       │   {DEVELOPER}          │
                       │   • make run-backing-services   (once)
                       │   • make server                 (each session)
                       │   • opens the browser           │
                       └───────────┬────────────┘
                                   │ browser — ONE origin
                                   ▼
   ┌──────────────────────────────────────────────────────────────┐
   │  {PHOENIX}  atomic-fi  :4100   — the only application backend │
   │  ── runs natively (iex -S mix phx.server) ──                  │
   │                                                                │
   │    GET /demo/*        example apps + index — static files     │
   │    GET /api/docs      Scalar API reference (CDN, build-free)   │
   │    /api/rules…        REST                                     │
   │    /api/screening…    REST ───────────────┐                    │
   │    /api/parse         document parser ────┤                    │
   │    /api/copilot       copilot runtime ────┤                    │
   │         │     │                           ▼                     │
   │         │     │                  ┌──────────────────┐          │
   │         │     │                  │ {OLLAMA} :11434  │          │
   │         │     │                  │ native daemon —  │          │
   │         │     │                  │ no keys          │          │
   │         ▼     ▼                  └──────────────────┘          │
   │   ┌─────────┐ ┌──────────┐                                     │
   │   │ ZenRule │ │ Watchman │   ◄── {BACKING SERVICES}            │
   │   │ :8090   │ │ :8084    │       Docker Compose. REQUIRED.     │
   │   └─────────┘ └──────────┘       `make run-backing-services`.  │
   └────────────────────────────────────────────────────────────────┘

   ────────────────────────────────────────────────────────────────
   ONE idiomatic Phoenix app. Example apps stay SEPARATE Vite builds
   (no SPA fold) — Phoenix just serves their static output. The
   browser hits one origin: no proxy, no CORS, no :5173.
   GONE: Python/uv document-agent · Node/tsx copilot sidecar.
```

---

## 2. `/demo` — example-app hosting

Each example app stays its own Vite project. Phoenix serves the built
output as plain static files. **No controller, no SPA fold.**

```
   plug Plug.Static, at: "/demo",
        from: {:atomic_fi, "priv/static/demo"}

   priv/static/demo/
     index.html    ← hand-written, CHECKED INTO GIT. an ever-growing
                     <ul> of links — add one <a> per example app.
     onboarding/   ← onboarding-flow       base "/demo/onboarding/"   ┐
     jdm/          ← atomic-fi-jdm-editor  base "/demo/jdm/"          ┼ gitignored
     lotus/        ← lotus-embed           base "/demo/lotus/"        ┘ (build output)

   per-app vite.config.ts — the ONLY per-app change:
     base:              "/demo/<app>/"
     build.outDir:      "<…>/priv/static/demo/<app>"
     build.emptyOutDir: true

   NO DemoController
   ────────────────────────────────────────────────────────────────
   The index is a static file. Plug.Static serves everything.
   • URL is /demo/index.html.
   • want a bare /demo ? one router redirect line — still no
     controller.
   • adding an example app = a new <a> in index.html + that app's
     vite.config base/outDir. nothing else.

   CAVEAT — SPA deep links
   ────────────────────────────────────────────────────────────────
   Plug.Static serves files, not SPA fallbacks. A demo opened at its
   root (/demo/jdm/) works as-is. Only an app that needs browser-
   history deep links would need a fallback route — decide per app;
   most demos don't.

   REGENERATION
   ────────────────────────────────────────────────────────────────
   dev   Phoenix endpoint `watchers:` runs `vite build --watch` per
         app → priv/static/demo/<app> rebuilt on change.
         live_reload watches priv/static/demo/.* → browser refresh.
   prod  Dockerfile build stage runs the builds once → baked into
         the release. SAME Plug.Static serves it. (see §8)
```

---

## 3. `make` surface + ports

**No new make targets.** The existing `make server` is the entry point.

```
   make run-backing-services   docker compose up ZenRule + Watchman.
                               PREREQUISITE — run once per boot.

   make server                 the EXISTING target —
                               iex -S mix phx.server.
                               Phoenix endpoint `watchers` rebuild
                               the example apps on change. No
                               Procfile, no separate Vite server.

   make seed                   ecto.setup + corpus seed

   `make run` is dropped — once the Vite builds became endpoint
   watchers it added nothing over `make server`.

   PROCESS        PORT          HOW IT RUNS
   ────────────────────────────────────────────────────────────────
   Ollama daemon  11434         native install
   Phoenix        4100          native — make server
   ZenRule        8090          Docker backing service
   Watchman       8084 / 9094   Docker backing service
   (no :5173 — Vite runs as a build-watcher, not a dev server)
```

---

## 4. Document parser — `POST /api/parse`

Replaces the Python `document-agent-server`. Folded into Phoenix as
`AtomicFi.DocumentParser`. No protocol — request → model → JSON.

```
   POST /api/parse        multipart:  files[]  +  metadata[]
   ─────────────────────────────────────────────────────────────────
   each file
     ├─ PDF ──► poppler ──┬─ pdftoppm   → page image(s)
     │                    └─ pdftotext  → text layer
     │                       (text-dense docs: statements, memoranda)
     └─ image ──────────────────────────────────────────────►
                          │
                          ▼
   ┌─────────────────────────────────────────────────────────────┐
   │  Instructor  +  Ollama          ONE LLM library, one call   │
   │   • page image(s) sent in the chat message → Ollama vision  │
   │   • Ecto embedded schema  (@llm_doc describes it)           │
   │   • validate_changeset/1  — semantic validation             │
   │   • max_retries           — re-prompt on invalid output     │
   └────────────────────────────┬────────────────────────────────┘
                                 ▼
   {:ok, %IdentityDocument{} | %BankStatement{}
         | %MemorandumOfAssociation{} | %Custom{}}      ◄── 6 schemas
                                                            (ex-Pydantic)

   ONE SPIKE — not an architecture branch
   ────────────────────────────────────────────────────────────────
   Confirm Instructor's Ollama adapter forwards a per-message
   `images:` field.
     • forwards it  → done. pure Instructor + Ollama.
     • strips it    → the vision call drops to the raw `ollama`
                      Elixir client (definitely carries `images:`);
                      Instructor/Ecto still does the validation.
   ReqLLM is NOT used here either way — it belongs to the copilot
   runtime only (§5). Instructor is the parser's LLM layer.

   PROVIDER:  ollama:<model> local default, no keys. poppler does
              the PDF→image step Ollama can't.
   RISK:      local models < Gemini on dense multi-page docs.
              gate = tests/test_extract.py — measure the delta.
```

---

## 5. Copilot runtime — `POST /api/copilot`

Replaces the Node `jdm-copilot-runtime`. Folded into Phoenix as
`AtomicFiWeb.Copilot`, **modeled on `Lotus.AI` + `Lotus.AI.Tool`**
(vendored in `deps/lotus`, ReqLLM-based).

```
   editor  src/copilot/      ──chat──►   AtomicFiWeb.Copilot
   (drops @copilotkit/runtime client;                │
    keeps the preview-card UX)                        │
                                                      ▼
                          ┌──────────────────────────────────┐
                          │  tool-calling loop                │
                          │  (port of Lotus.AI.Tool.run/4)    │
                          │  ReqLLM.generate_text(.., tools:) │
                          │      → classify response          │
                          └───────────────┬───────────────────┘
                                           │ :tool_calls
                          ┌────────────────┴─────────────────┐
                          ▼                                  ▼
               ╔══════════════════════╗        ╔══════════════════════╗
               ║ SERVER TOOLS         ║        ║ CLIENT TOOLS         ║
               ║ run in-process as    ║        ║ canvas-bound — run   ║
               ║ Lotus.AI.Action      ║        ║ in the browser       ║
               ║                      ║        ║                      ║
               ║   save_rule          ║        ║   add_node           ║
               ║   simulate_rule →Zen ║        ║   graph mutations    ║
               ║   list rules         ║        ║                      ║
               ║                      ║        ║ loop emits the call  ║
               ║ ← satisfies C3:      ║        ║ over a Phoenix       ║
               ║   real atomic-fi     ║        ║ Channel, pauses,     ║
               ║   HTTP/Action calls  ║        ║ resumes on result    ║
               ╚══════════╤═══════════╝        ╚══════════╤═══════════╝
                          └────────────┬──────────────────┘
                                       ▼
                          result appended → recurse to max_iterations
                                       ▼
                              final text response → editor

   REUSED FROM Lotus (deps/lotus/lib/lotus/ai/):
     ai.ex  ai/tool.ex  ai/action.ex  ai/conversation.ex
   NEW vs Lotus:   the CLIENT TOOL branch (browser round-trip).
   NOT REIMPLEMENTED:  CopilotKit's GraphQL runtime protocol.
```

---

## 6. Backing services — Docker this iteration

```
   SERVICE     ROLE                    THIS ITERATION   FUTURE (own ADR)
   ────────────────────────────────────────────────────────────────────
   ZenRule     JDM rules engine        Docker Compose   EMBED — Rustler
               (GoRules Zen, Rust)                      NIF over `zen-
                                                        engine` crate.
   Watchman    sanctions screening     Docker Compose   SUPERVISE — Go
               (moov, Go service)                       binary as an OTP
                                                        Port child.

   No native Elixir JDM library exists. Native interop = deferred,
   not dropped. `make server` never depends on it.
```

---

## 7. LLM stack

Two libraries, each where it is idiomatic — **not one spine**.

```
   document parser   →  Instructor              →  Ollama
   (§4)                 structured extraction:
                        Ecto schema + changeset + max_retries
                        fallback image transport: `ollama` client

   copilot runtime   →  ReqLLM (via Lotus.AI)   →  Ollama
   (§5)                 chat + tool-calling; Lotus.AI is already
                        built on ReqLLM — we inherit it, not add it

                        Ollama :11434 — local, no keys.

   SECRETS:  one root `.env`. Today a Google API key is hand-copied
             across 3 git-ignored files (never committed). The Ollama
             default needs no key — those references are just removed.
```

---

## 8. Deployment (Fly) — falls out for free

Because Phoenix owns `priv/static/demo`, the example apps are not a
separate deployable. One Fly app, one image, one `fly deploy`.

```
   how files reach priv/static/demo
   ────────────────────────────────────────────────────────────────
   DEV    config/dev.exs `watchers:`     vite build --watch (per app)
   PROD   Dockerfile build stage         pnpm build (per app, once)
                                         → mix assets.deploy → digest
                                         → baked into mix release
   SHARED  plug Plug.Static, at: "/demo"  — identical dev + prod

   WHY SIMPLER
   ────────────────────────────────────────────────────────────────
   • one Fly app / image / deploy — no separate static host, no CDN
     bucket, no second app for the frontend
   • same origin (atomic-fi.alvera.ai/demo + /api) — no CORS, one
     TLS cert, one domain
   • SPA fingerprinted into the SAME release as the API — no skew
   • only Dockerfile change: add a Node build stage in front of the
     Elixir release build; runtime image unchanged
```

---

## 9. Migration checklist

```
   [ ] remove unused GOOGLE_API_KEY references (3 git-ignored files —
       never committed; Ollama local needs no key)
   [ ] per example app: vite.config base + outDir → priv/static/demo/<app>
   [ ] priv/static/demo/index.html — static, checked in, list of <a>
       links; plug Plug.Static, at: "/demo"
   [ ] config/dev.exs: one `vite build --watch` watcher per app;
       live_reload pattern priv/static/demo/.*
   [ ] AtomicFi.DocumentParser + /api/parse — Instructor + Ollama,
       poppler raster, 6 Ecto schemas; spike Instructor image input;
       re-run tests/test_extract.py; retire document-agent-server
   [ ] AtomicFiWeb.Copilot + /api/copilot — Lotus.AI pattern; server
       Actions + client round-trip; rework editor src/copilot/;
       retire jdm-copilot-runtime + the atomic-fi-jdm worktree
   [ ] point Lotus AI config at Ollama
   [ ] root .env; drop onboarding-flow bun.lockb; gitignore
       priv/static/demo/<app> dirs (keep index.html)
   [ ] Dockerfile: add Node build stage for the example apps
   [ ] CI smoke test — boot stack, health-check every route
```
