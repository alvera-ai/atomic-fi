import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { OpenAIAdapter, AnthropicAdapter } from '@copilotkit/runtime';
import { selectAdapter } from '../src/adapters/index';

const originalEnv = { ...process.env };

beforeEach(() => {
  process.env = { ...originalEnv };
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe('selectAdapter', () => {
  it('returns an OpenAIAdapter when provider=openai', () => {
    process.env.OPENAI_API_KEY = 'sk-test';
    const adapter = selectAdapter({ provider: 'openai' });
    expect(adapter).toBeInstanceOf(OpenAIAdapter);
  });

  it('returns an AnthropicAdapter when provider=anthropic', () => {
    process.env.ANTHROPIC_API_KEY = 'ant-test';
    const adapter = selectAdapter({ provider: 'anthropic' });
    expect(adapter).toBeInstanceOf(AnthropicAdapter);
  });

  it('throws for unknown providers', () => {
    expect(() => selectAdapter({ provider: 'bogus' as never })).toThrow(
      /Unknown LLM_PROVIDER/,
    );
  });

  it('throws a helpful error when API key is missing', () => {
    delete process.env.OPENAI_API_KEY;
    expect(() => selectAdapter({ provider: 'openai' })).toThrow(
      /OPENAI_API_KEY is required/,
    );
  });
});
