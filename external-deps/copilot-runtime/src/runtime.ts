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
 * This runtime is generic: it injects no system prompt. The calling app's
 * instructions arrive as system/developer messages and are forwarded to the
 * model via the `forward*Messages` options.
 */
export const aisdkFactory: BuiltInAgentAISDKFactoryConfig['factory'] = (ctx) => {
  const turnId = `turn-${++turnSeq}`;
  const messages = convertMessagesToVercelAISDKMessages(ctx.input.messages, {
    forwardSystemMessages: true,
    forwardDeveloperMessages: true,
  });
  const tools = convertToolsToVercelAITools(ctx.input.tools);

  log.info('llm.turn', {
    turn_id: turnId,
    provider: envProvider(),
    model: process.env.LLM_MODEL,
    messages: messages.length,
    tools: Object.keys(tools).length,
  });

  return streamText({
    model: pickModel(),
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
