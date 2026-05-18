# @atomic-fi/jdm-copilot-runtime

Small Node sidecar that hosts the CopilotKit runtime for the JDM editor.
The browser sends chat traffic here at `POST /api/copilotkit`, the sidecar
brokers the call out to OpenAI or Anthropic, and tool calls are rendered
back as preview cards in the editor's chat panel.

## What's inside

```
src/
├── server.ts          # Hono app + /healthz + /api/copilotkit mount
├── runtime.ts         # CopilotRuntime + system-prompt injection
├── logger.ts          # Structured timestamped logger
├── adapters/
│   ├── index.ts       # env-driven adapter selector
│   ├── openai.ts      # OpenAIAdapter wrapper
│   └── anthropic.ts   # AnthropicAdapter wrapper
└── prompts/
    ├── system.md      # Authored system prompt (read at boot)
    └── system.ts      # Loader (readFileSync)

tests/
├── adapters.test.ts       # selectAdapter cases
└── server.smoke.test.ts   # /healthz + /api/copilotkit mount smoke
```

The sidecar holds **no** business logic — every action the agent can
take (`add_node`, `save_rule`, `simulate_rule`, …) is defined in the
editor's React code and runs in the browser. The sidecar's only jobs
are LLM brokering and system-prompt injection.

## Prerequisites

- Node 22+ and pnpm.
- An OpenAI API key (default) or Anthropic API key.
- `pnpm install` run once from the repo root.

## Configuration

Copy the example and fill in your key:

```bash
cp .env.example .env.local
```

Then edit `.env.local`:

```env
# Provider — "openai" (default) or "anthropic".
LLM_PROVIDER=openai

# Optional model override. Defaults: gpt-4o-mini / claude-sonnet-4-6.
# LLM_MODEL=gpt-4o

# Set whichever matches LLM_PROVIDER.
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=

# Optional. Default: 4111.
PORT=4111

# Optional. Set to "debug" to see per-tool-call args/results in logs.
# LOG_LEVEL=debug
```

`.env.local` is preferred (loaded first); `.env` is a fallback. Both are
gitignored.

### Model recommendations

| Model | Quality | Cost | Notes |
|---|---|---|---|
| `gpt-4o-mini` (default) | Good | Cheapest | Works for the bundled flows. Occasionally drops nested-object tool args (we route around it via JSON-string forms). |
| `gpt-4o` | Very good | ~30× | More reliable for nested-object args and complex rule authoring. |
| `claude-sonnet-4-6` | Very good | ~comparable to gpt-4o | Handles complex tool args natively. Set `LLM_PROVIDER=anthropic`. |

## Running

```bash
pnpm install   # if you haven't already
pnpm dev       # tsx watch on src/server.ts
```

You should see:

```
2026-05-18T... [INFO ] runtime.built provider=openai model=(adapter default)
2026-05-18T... [INFO ] server.listening port=4111 pid=NNNNN node=v22.x.x log_level=info
```

Verify with a quick `curl`:

```bash
curl http://localhost:4111/healthz
# → {"ok":true,"provider":"openai"}
```

The editor's Vite dev server proxies `/api/copilotkit → :4111`. You don't
hit `:4111` from the browser directly.

## Building for production

```bash
pnpm build    # tsc → ./dist
pnpm start    # node dist/server.js
```

## Tests

```bash
pnpm test     # vitest run (7 cases)
```

## Logs and debugging

Every request logs a `http.request` / `http.response` pair with a `req_id`,
method, path, status, and duration. Every chat turn logs an
`llm.request.received` line with the message count, kinds, and a preview
of the last user message. The system-prompt injection is confirmed by a
`llm.request.system_prompt_injected` line.

For deeper inspection, set `LOG_LEVEL=debug` in `.env.local` and you'll
also get per-tool-call args (`llm.request.tool_call`) and per-tool-result
contents (`llm.request.tool_result`). These are truncated to 300 chars
and exclude API keys, but otherwise show exactly what the agent is
trying to do.

Common log events:

| Event | When |
|---|---|
| `server.listening` | Process boot |
| `runtime.built` | First app instance constructed |
| `http.request` / `http.response` | Every inbound HTTP call with `req_id` |
| `http.exception` / `copilotkit.handler.exception` | A handler threw |
| `llm.request.received` | A chat turn arrived from the editor |
| `llm.request.system_prompt_injected` | Confirms the prompt landed in `inputMessages` |
| `llm.request.tool_call` / `llm.request.tool_result` | Debug-only; per-action visibility |
| `process.unhandledRejection` / `uncaughtException` | Crash-safety logs |

## Editing the system prompt

`src/prompts/system.md` is read once at sidecar boot. After editing,
**restart the sidecar** (Ctrl-C → `pnpm dev`). The editor's HMR does NOT
restart the Node process.

The prompt is a port of the `.claude/skills/zenrule-author/SKILL.md`
authoring discipline, adapted for in-app tool verbs. A header comment
points back to the source for drift detection.

## Architecture

See `docs/superpowers/specs/2026-05-18-copilotkit-rules-design.md` for
the full design (topology, action catalog, readables, UX flow). For the
zenrule-author skill the prompt mirrors, see
`.claude/skills/zenrule-author/SKILL.md`.
