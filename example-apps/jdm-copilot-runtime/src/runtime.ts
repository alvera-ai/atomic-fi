import { CopilotRuntime } from '@copilotkit/runtime';
import { selectAdapter, type Provider, type ServiceAdapter } from './adapters/index';
import { SYSTEM_PROMPT } from './prompts/system';
import { log, truncate } from './logger';

let turnSeq = 0;

// Best-effort introspection helpers — the runtime's `Message` class isn't
// exported, so we have to read fields off duck-typed shapes. Kept tolerant
// so a CopilotKit minor-version bump doesn't crash logging.

type MessageLike = {
  role?: string;
  content?: unknown;
  type?: string;
  name?: string;
  arguments?: unknown;
  isTextMessage?: () => boolean;
  isActionExecutionMessage?: () => boolean;
  isResultMessage?: () => boolean;
};

function classifyMessage(m: MessageLike): string {
  try {
    if (m.isActionExecutionMessage?.()) return 'tool_call';
    if (m.isResultMessage?.()) return 'tool_result';
    if (m.isTextMessage?.()) return typeof m.role === 'string' ? m.role : 'text';
  } catch {
    /* fall through */
  }
  if (m.role) return String(m.role);
  if (m.type) return String(m.type);
  return 'unknown';
}

function lastUserText(messages: readonly MessageLike[]): string | null {
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    if (m && m.role === 'user' && typeof m.content === 'string') {
      return m.content;
    }
  }
  return null;
}

export function buildRuntime(): { runtime: CopilotRuntime; serviceAdapter: ServiceAdapter; provider: Provider } {
  const provider = (process.env.LLM_PROVIDER ?? 'openai') as Provider;
  const serviceAdapter = selectAdapter({
    provider,
    model: process.env.LLM_MODEL,
  });
  // Inject SYSTEM_PROMPT as a system-role message on every chat completion.
  //
  // CopilotRuntime exposes a `middleware.onBeforeRequest` hook that receives the
  // `inputMessages` array (the converted-from-GraphQL `Message[]` that gets passed
  // straight into `serviceAdapter.process({ messages, ... })`). The runtime keeps a
  // reference to this array — mutating it in place is the supported way to alter
  // the prompt at the runtime layer in @copilotkit/runtime@1.10.5.
  //
  // We unshift a duck-typed TextMessage whose shape matches the runtime's
  // internal `Message` class: it carries the same `type`/`role`/`content` fields
  // plus the `isTextMessage()`/`isXxxMessage()` predicates the OpenAI and
  // Anthropic adapters call when filtering and converting messages. The classes
  // themselves aren't exported from `@copilotkit/runtime`, hence the duck type.
  const runtime = new CopilotRuntime({
    middleware: {
      onBeforeRequest: (ctx) => {
        const turnId = `turn-${++turnSeq}`;
        const inputMessages = (ctx as { inputMessages: MessageLike[] }).inputMessages;
        const properties = (ctx as { properties?: Record<string, unknown> }).properties;

        // Tally what's on the wire BEFORE we inject. Useful for diagnosing
        // hung agents — you can see exactly which tool_call/tool_result pairs
        // are present and whether the agent is mid-multi-call.
        const tally: Record<string, number> = {};
        for (const m of inputMessages) {
          const cls = classifyMessage(m);
          tally[cls] = (tally[cls] ?? 0) + 1;
        }
        const userText = lastUserText(inputMessages);

        log.info('llm.request.received', {
          turn_id: turnId,
          provider,
          model: process.env.LLM_MODEL ?? '(adapter default)',
          messages_total: inputMessages.length,
          messages_by_kind: tally,
          last_user_message: truncate(userText, 240),
          properties_keys: properties ? Object.keys(properties) : [],
        });

        // Per-tool-call debug visibility (only on LOG_LEVEL=debug). Spot
        // whether the agent re-emitted a tool call after a respond didn't
        // land, or which tool_call IDs are unresolved.
        for (const m of inputMessages) {
          if (m.isActionExecutionMessage?.()) {
            log.debug('llm.request.tool_call', {
              turn_id: turnId,
              tool: m.name,
              args: truncate(typeof m.arguments === 'string' ? m.arguments : JSON.stringify(m.arguments ?? {}), 300),
            });
          } else if (m.isResultMessage?.()) {
            log.debug('llm.request.tool_result', {
              turn_id: turnId,
              tool: m.name,
              result: truncate(typeof m.content === 'string' ? m.content : JSON.stringify(m.content ?? {}), 300),
            });
          }
        }

        const systemMessage = {
          id: 'jdm-system-prompt',
          createdAt: new Date(),
          type: 'TextMessage' as const,
          role: 'system' as const,
          content: SYSTEM_PROMPT,
          isTextMessage: () => true,
          isActionExecutionMessage: () => false,
          isResultMessage: () => false,
          isAgentStateMessage: () => false,
          isImageMessage: () => false,
        };
        // Cast through unknown because the runtime's `Message` class isn't
        // exported; we ship a structurally-compatible value instead.
        inputMessages.unshift(systemMessage as unknown as (typeof inputMessages)[number]);

        log.info('llm.request.system_prompt_injected', {
          turn_id: turnId,
          prompt_bytes: SYSTEM_PROMPT.length,
          messages_after_injection: inputMessages.length,
        });
      },
    },
    // Zero server-side actions; every action runs in the browser.
  });
  return { runtime, serviceAdapter, provider };
}
