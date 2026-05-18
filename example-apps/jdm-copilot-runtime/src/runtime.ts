import { CopilotRuntime } from '@copilotkit/runtime';
import { selectAdapter, type Provider, type ServiceAdapter } from './adapters/index';
import { SYSTEM_PROMPT } from './prompts/system';

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
      onBeforeRequest: ({ inputMessages }) => {
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
      },
    },
    // Zero server-side actions; every action runs in the browser.
  });
  return { runtime, serviceAdapter, provider };
}
