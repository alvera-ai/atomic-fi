import Anthropic from '@anthropic-ai/sdk';
import { AnthropicAdapter } from '@copilotkit/runtime';

export function makeAnthropicAdapter(opts: { model?: string }): AnthropicAdapter {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    throw new Error(
      'ANTHROPIC_API_KEY is required when LLM_PROVIDER=anthropic. ' +
        'Set it in example-apps/jdm-copilot-runtime/.env.local',
    );
  }
  const anthropic = new Anthropic({ apiKey });
  return new AnthropicAdapter({
    anthropic,
    model: opts.model ?? 'claude-sonnet-4-6',
  });
}
