import {
  BuiltInAgent,
  CopilotRuntime,
  convertMessagesToVercelAISDKMessages,
  convertToolsToVercelAITools,
  type BuiltInAgentAISDKFactoryConfig,
} from '@copilotkit/runtime/v2';
import { streamText } from 'ai';
import { pickModel, envProvider } from './models/index';
import { log } from './logger';

let turnSeq = 0;

/**
 * The `"aisdk"` Factory Mode function. On each agent turn we own the LLM
 * call: convert the AG-UI messages + tools to Vercel AI SDK shapes, run
 * `streamText`, and return the result — CopilotKit consumes its `fullStream`
 * and converts it to AG-UI events.
 *
 * Factory Mode gives us full control of the message array, so we MUST
 * project `ctx.input.context[]` (readables registered client-side via
 * `useAgentContext`) into a leading system message ourselves — the runtime's
 * default builtin agent does this at `agent/index.cjs:363-370`, and bypassing
 * it without re-doing the projection makes the LLM blind to the client state
 * (the open graph, schema, cheatsheet, …).
 */
export const aisdkFactory: BuiltInAgentAISDKFactoryConfig['factory'] = (ctx) => {
  // Test seam — set RUNTIME_DEBUG_THROW=1 to force an immediate factory
  // throw on every turn. CopilotKit's BuiltInAgent catches the exception
  // and emits a RUN_ERROR AG-UI event back to the client; this is how we
  // verify the end-to-end error path lights up the chat UI without
  // having to take Ollama down or feed in a bad model name.
  if (process.env.RUNTIME_DEBUG_THROW === '1') {
    throw new Error('RUNTIME_DEBUG_THROW=1 — forced factory throw for error-path testing');
  }
  const turnId = `turn-${++turnSeq}`;
  const messages = convertMessagesToVercelAISDKMessages(ctx.input.messages, {
    forwardSystemMessages: true,
    forwardDeveloperMessages: true,
  });
  const tools = convertToolsToVercelAITools(ctx.input.tools);

  // Project AG-UI readables into the system prompt — same shape the v1
  // runtime emitted, so v1 behaviour carries over to the v2 stack. Use the
  // dedicated `system` option (not an injected system message) — AI SDK
  // flags system-in-messages as a prompt-injection vector.
  const contextItems = ctx.input.context ?? [];
  const system =
    contextItems.length > 0
      ? `The following information is available to you:\n\n${contextItems
          .map((c) => `${c.description}:\n${c.value}\n`)
          .join('\n')}`
      : undefined;

  log.info('llm.turn', {
    turn_id: turnId,
    provider: envProvider(),
    model: process.env.LLM_MODEL,
    messages: messages.length,
    context_items: contextItems.length,
    tools: Object.keys(tools).length,
  });

  return streamText({
    model: pickModel(),
    system,
    messages,
    tools,
    abortSignal: ctx.abortSignal,
  });
};

/**
 * Build the v2 CopilotRuntime — a single `BuiltInAgent` in `"aisdk"` Factory
 * Mode. `agents.default` is the agent the calling CopilotKit client targets.
 */
export function buildRuntime(): CopilotRuntime {
  const agent = new BuiltInAgent({ type: 'aisdk', factory: aisdkFactory });
  return new CopilotRuntime({ agents: { default: agent } });
}
