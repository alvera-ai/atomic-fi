import type { LanguageModel } from 'ai';
import { createOpenAI } from '@ai-sdk/openai';
import { createAnthropic } from '@ai-sdk/anthropic';
import { createGoogleGenerativeAI } from '@ai-sdk/google';
import { createGroq } from '@ai-sdk/groq';
import { createOllama } from 'ollama-ai-provider-v2';
import { createOpenAICompatible } from '@ai-sdk/openai-compatible';

/**
 * Provider toggle: five native Vercel AI SDK providers plus an
 * OpenAI-compatible fallback (vLLM, LM Studio, LiteLLM, Ollama's own /v1 — any
 * server speaking the OpenAI chat-completions API).
 */
export type Provider = 'openai' | 'anthropic' | 'google' | 'groq' | 'ollama' | 'compatible';

const PROVIDERS: readonly Provider[] = [
  'openai',
  'anthropic',
  'google',
  'groq',
  'ollama',
  'compatible',
];

/** The validated `LLM_PROVIDER` env value. Defaults to `ollama`. */
export function envProvider(): Provider {
  const raw = process.env.LLM_PROVIDER ?? 'ollama';
  if (!(PROVIDERS as readonly string[]).includes(raw)) {
    throw new Error(
      `Unknown LLM_PROVIDER "${raw}". Expected one of: ${PROVIDERS.join(', ')}.`,
    );
  }
  return raw as Provider;
}

function requireEnv(key: string): string {
  const value = process.env[key];
  if (!value) {
    throw new Error(`${key} is required for LLM_PROVIDER=${envProvider()}.`);
  }
  return value;
}

/**
 * Resolve the active LLM as a Vercel AI SDK `LanguageModel`, chosen entirely
 * from environment. A missing required variable fails loud — no silent
 * fallback.
 */
export function pickModel(): LanguageModel {
  const provider = envProvider();
  const model = requireEnv('LLM_MODEL');

  switch (provider) {
    case 'openai':
      return createOpenAI({ apiKey: requireEnv('OPENAI_API_KEY') })(model);
    case 'anthropic':
      return createAnthropic({ apiKey: requireEnv('ANTHROPIC_API_KEY') })(model);
    case 'google':
      return createGoogleGenerativeAI({ apiKey: requireEnv('GOOGLE_API_KEY') })(model);
    case 'groq':
      return createGroq({ apiKey: requireEnv('GROQ_API_KEY') })(model);
    case 'ollama': {
      // Ollama's native API. baseURL is optional — the provider defaults to
      // http://localhost:11434/api; in Docker it points at host.docker.internal.
      const baseURL = process.env.OLLAMA_BASE_URL;
      return createOllama(baseURL ? { baseURL } : {})(model);
    }
    case 'compatible':
      // Any OpenAI-compatible server. The key is optional — local servers
      // (Ollama /v1, vLLM, LM Studio) ignore it.
      return createOpenAICompatible({
        name: process.env.LLM_COMPATIBLE_NAME ?? 'compatible',
        baseURL: requireEnv('LLM_BASE_URL'),
        apiKey: process.env.LLM_API_KEY,
      })(model);
  }
}
