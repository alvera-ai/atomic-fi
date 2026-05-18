import OpenAI from 'openai';
import { OpenAIAdapter } from '@copilotkit/runtime';

export function makeOpenAIAdapter(opts: { model?: string }): OpenAIAdapter {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    throw new Error(
      'OPENAI_API_KEY is required when LLM_PROVIDER=openai. ' +
        'Set it in example-apps/jdm-copilot-runtime/.env.local',
    );
  }
  const openai = new OpenAI({ apiKey });
  return new OpenAIAdapter({
    // Cast: @copilotkit/runtime is compiled against a newer openai SDK than the
    // one pinned here; runtime shape is compatible.
    openai: openai as never,
    model: opts.model ?? 'gpt-4o-mini',
  });
}
