# @atomic-fi/jdm-copilot-runtime

Tiny Node sidecar that hosts the CopilotKit runtime for the JDM editor.

## Run

```bash
cp .env.example .env.local
# set OPENAI_API_KEY (or ANTHROPIC_API_KEY + LLM_PROVIDER=anthropic)
pnpm install
pnpm dev
```

The sidecar listens on `:4111`. The editor's Vite dev server proxies
`/api/copilotkit → http://localhost:4111` (see editor's `vite.config.ts`).

## Architecture

See `docs/superpowers/specs/2026-05-18-copilotkit-rules-design.md`.
