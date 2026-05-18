import { makeOpenAIAdapter } from './openai';
import { makeAnthropicAdapter } from './anthropic';
import type { OpenAIAdapter, AnthropicAdapter } from '@copilotkit/runtime';

export type Provider = 'openai' | 'anthropic';
export type ServiceAdapter = OpenAIAdapter | AnthropicAdapter;

export function selectAdapter(opts: {
  provider: Provider;
  model?: string;
}): ServiceAdapter {
  switch (opts.provider) {
    case 'openai':
      return makeOpenAIAdapter({ model: opts.model });
    case 'anthropic':
      return makeAnthropicAdapter({ model: opts.model });
    default:
      throw new Error(
        `Unknown LLM_PROVIDER: ${opts.provider}. Expected "openai" or "anthropic".`,
      );
  }
}
