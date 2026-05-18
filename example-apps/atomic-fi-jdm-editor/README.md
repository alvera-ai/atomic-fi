# atomic-fi JDM editor

Local JDM (JSON Decision Model) authoring + simulation tool for atomic-fi.

Vendored from [gorules/editor](https://github.com/gorules/editor) at upstream SHA
`1a413b3d47e8dab56d85fbd62d9b9a795d57ca6a`. Frontend only — the simulator routes to the
ZenRule agent that the parent atomic-fi project already runs locally (see
`local-dependencies.yaml`).

## Prerequisites

- Node 22+ and pnpm.
- Docker (for the ZenRule agent).
- Have run `pnpm install` once at the repository root.

## Quickstart

From the repo root:

```bash
docker compose -f local-dependencies.yaml up -d zenrule
pnpm --filter @atomic-fi/jdm-editor dev
```

Open the Vite dev URL printed in the terminal (typically `http://localhost:5173`).

## What works

- **Open** a JDM file from disk (FileSystem Access API; falls back to a hidden
  `<input type="file">` in Firefox/Safari).
- **Edit** rules visually.
- **Save** (FS API) or **Save As** (download) back to disk.
- **Simulate** the saved file against a JSON context. The simulator routes to
  the ZenRule agent at `http://localhost:8090` via a Vite dev-proxy.

## What does not work yet

- **Simulating unsaved drafts.** The ZenRule agent has no inline simulate
  endpoint — it only evaluates files saved under `priv/zenrule/atomic-fi/`. So
  the current workflow is **Save → Simulate** (also documented as
  `TODO(draft-state)` in `src/helpers/simulator.ts`). See the spec at
  `docs/superpowers/specs/2026-05-13-jdm-editor-scaffold-design.md` for the
  followup paths.
- **No Phoenix integration yet.** All I/O is local FS.

## Upstream divergence

Modifications from upstream (`gorules/editor` @ pinned SHA):

- Stripped Rust backend (`backend/`, `Cargo.toml`, `Dockerfile`, `Makefile`, …).
- `src/helpers/simulator.ts` is new; replaces upstream's inline axios call.
- `vite.config.ts` proxy retargeted from `:3000` (upstream Rust) to `:8090`
  (atomic-fi's ZenRule agent); HTTPS dev-server block removed.
- `package.json` name → `@atomic-fi/jdm-editor`.
- README replaced.
- Page-header heading rebranded.

## License

Upstream `gorules/editor` is MIT (see `LICENSE`). Our modifications are
distributed under the parent atomic-fi license.

## AI rule copilot

The editor includes an AI sidebar (CopilotKit) on the rule-edit route
(`/rules/:ruleType/:name`). It needs a sidecar runtime:

```bash
# In a separate terminal:
cp example-apps/jdm-copilot-runtime/.env.example example-apps/jdm-copilot-runtime/.env.local
# edit OPENAI_API_KEY (or set LLM_PROVIDER=anthropic + ANTHROPIC_API_KEY)
pnpm --filter @atomic-fi/jdm-copilot-runtime dev
```

The sidecar listens on `:4111`. The editor's Vite proxy forwards
`/api/copilotkit` to it.

Design notes: `docs/superpowers/specs/2026-05-18-copilotkit-rules-design.md`.
