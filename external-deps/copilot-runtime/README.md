# @atomic-fi/copilot-runtime

A **generic** [CopilotKit](https://copilotkit.ai) runtime sidecar. It hosts the
CopilotKit **v2 runtime** in **Factory Mode** over the **Vercel AI SDK**, so a
browser CopilotKit client can run agent turns against any configured LLM.

It holds **no domain logic** — no prompts, no actions, no app-specific code.
The calling app owns its instructions and tools; this service only brokers LLM
turns and speaks the CopilotKit / AG-UI transport.

## Stack

```
Bun.serve → Hono → @copilotkit/runtime/v2  (createCopilotHonoHandler)
          → CopilotRuntime → BuiltInAgent ("aisdk" Factory Mode)
          → Vercel AI SDK streamText → the model provider
```

CopilotKit ships `@copilotkit/runtime` as library middleware, not a server and
not an official image — this is the thin host it expects you to write.

## Endpoints

| Route | Purpose |
|---|---|
| `GET /healthz` | liveness — `{ "ok": true, "provider": "<provider>" }` |
| `/api/copilotkit/*` | the CopilotKit v2 runtime (AG-UI) |

## Configuration

All behaviour is environment-driven — `LLM_PROVIDER` toggles the provider,
`LLM_MODEL` picks the model. A missing required variable fails loud.

| Variable | Used when | Notes |
|---|---|---|
| `LLM_PROVIDER` | always | `openai` `anthropic` `google` `groq` `ollama` `compatible` (default `ollama`) |
| `LLM_MODEL` | always | model id, e.g. `qwen3.5:9b`, `gpt-4o` |
| `OLLAMA_BASE_URL` | `ollama` | optional; default `http://localhost:11434/api` |
| `LLM_BASE_URL` | `compatible` | OpenAI-compatible server base URL |
| `LLM_API_KEY` / `LLM_COMPATIBLE_NAME` | `compatible` | optional |
| `OPENAI_API_KEY` etc. | the matching cloud provider | |
| `PORT` | optional | default `4111` |
| `LOG_LEVEL` | optional | `debug` for per-turn detail |

Local dev: `cp .env.example .env.local` (bun auto-loads it). The Docker service
reads `docker.env`.

## Develop

```bash
bun install
bun run dev          # bun --watch src/main.ts
bun test             # bun:test — >=90% coverage gate
bun run typecheck    # tsc --noEmit
```

## Docker

Built and run as a backing service by `local-dependencies.yaml`
(`make run-backing-services`). `docker.env` is the behaviour knob — edit it,
`docker compose up -d` again, no rebuild.
