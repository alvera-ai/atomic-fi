import { CopilotRuntime } from '@copilotkit/runtime';
import { selectAdapter, type Provider, type ServiceAdapter } from './adapters/index';
import { SYSTEM_PROMPT } from './prompts/system';

export function buildRuntime(): { runtime: CopilotRuntime; serviceAdapter: ServiceAdapter; provider: Provider } {
  const provider = (process.env.LLM_PROVIDER ?? 'openai') as Provider;
  const serviceAdapter = selectAdapter({
    provider,
    model: process.env.LLM_MODEL,
  });
  const runtime = new CopilotRuntime({
    // Zero server-side actions; every action runs in the browser.
  });
  // Attach SYSTEM_PROMPT to the adapter so it's injected as the system
  // message on every LLM call. The selectAdapter factory stays generic
  // by not knowing about the prompt; we attach it post-hoc here.
  (serviceAdapter as unknown as { systemMessage?: string }).systemMessage = SYSTEM_PROMPT;
  return { runtime, serviceAdapter, provider };
}
