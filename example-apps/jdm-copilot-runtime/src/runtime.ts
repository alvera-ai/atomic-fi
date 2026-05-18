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
  // The runtime accepts a system prompt via instructions on each request,
  // but for a fixed app we inject it once via the adapter's default
  // system message. Each adapter accepts a `systemMessage` field at
  // construction time; we attach it post-hoc here so the selectAdapter
  // factory stays generic.
  (serviceAdapter as unknown as { systemMessage?: string }).systemMessage = SYSTEM_PROMPT;
  return { runtime, serviceAdapter, provider };
}
