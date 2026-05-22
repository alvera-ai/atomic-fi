import { afterEach, beforeEach, describe, expect, it } from 'bun:test';
import { envProvider, pickModel } from '../src/models/index';

const KEYS = [
  'LLM_PROVIDER',
  'LLM_MODEL',
  'OPENAI_API_KEY',
  'ANTHROPIC_API_KEY',
  'GOOGLE_API_KEY',
  'GROQ_API_KEY',
  'OLLAMA_BASE_URL',
  'LLM_BASE_URL',
  'LLM_API_KEY',
  'LLM_COMPATIBLE_NAME',
] as const;

const saved: Record<string, string | undefined> = {};

beforeEach(() => {
  for (const k of KEYS) {
    saved[k] = process.env[k];
    delete process.env[k];
  }
});

afterEach(() => {
  for (const k of KEYS) {
    if (saved[k] === undefined) delete process.env[k];
    else process.env[k] = saved[k];
  }
});

describe('envProvider', () => {
  it('defaults to ollama', () => {
    expect(envProvider()).toBe('ollama');
  });

  it('returns a valid provider verbatim', () => {
    process.env.LLM_PROVIDER = 'openai';
    expect(envProvider()).toBe('openai');
  });

  it('throws on an unknown provider', () => {
    process.env.LLM_PROVIDER = 'bogus';
    expect(() => envProvider()).toThrow(/Unknown LLM_PROVIDER/);
  });
});

describe('pickModel', () => {
  it('resolves openai', () => {
    process.env.LLM_PROVIDER = 'openai';
    process.env.LLM_MODEL = 'gpt-4o';
    process.env.OPENAI_API_KEY = 'sk-test';
    expect(pickModel()).toBeDefined();
  });

  it('resolves anthropic', () => {
    process.env.LLM_PROVIDER = 'anthropic';
    process.env.LLM_MODEL = 'claude-sonnet-4-5';
    process.env.ANTHROPIC_API_KEY = 'ant-test';
    expect(pickModel()).toBeDefined();
  });

  it('resolves google', () => {
    process.env.LLM_PROVIDER = 'google';
    process.env.LLM_MODEL = 'gemini-2.5-flash';
    process.env.GOOGLE_API_KEY = 'g-test';
    expect(pickModel()).toBeDefined();
  });

  it('resolves groq', () => {
    process.env.LLM_PROVIDER = 'groq';
    process.env.LLM_MODEL = 'llama-3.3-70b';
    process.env.GROQ_API_KEY = 'gq-test';
    expect(pickModel()).toBeDefined();
  });

  it('resolves ollama with the provider default base URL', () => {
    process.env.LLM_PROVIDER = 'ollama';
    process.env.LLM_MODEL = 'qwen3.5:9b';
    expect(pickModel()).toBeDefined();
  });

  it('resolves ollama with an explicit base URL', () => {
    process.env.LLM_PROVIDER = 'ollama';
    process.env.LLM_MODEL = 'qwen3.5:9b';
    process.env.OLLAMA_BASE_URL = 'http://host.docker.internal:11434/api';
    expect(pickModel()).toBeDefined();
  });

  it('resolves the openai-compatible fallback', () => {
    process.env.LLM_PROVIDER = 'compatible';
    process.env.LLM_MODEL = 'qwen3.5:9b';
    process.env.LLM_BASE_URL = 'http://localhost:11434/v1';
    expect(pickModel()).toBeDefined();
  });

  it('throws when LLM_MODEL is missing', () => {
    process.env.LLM_PROVIDER = 'ollama';
    expect(() => pickModel()).toThrow(/LLM_MODEL is required/);
  });

  it('throws when the provider key is missing', () => {
    process.env.LLM_PROVIDER = 'openai';
    process.env.LLM_MODEL = 'gpt-4o';
    expect(() => pickModel()).toThrow(/OPENAI_API_KEY is required/);
  });

  it('throws when the compatible fallback has no base URL', () => {
    process.env.LLM_PROVIDER = 'compatible';
    process.env.LLM_MODEL = 'qwen3.5:9b';
    expect(() => pickModel()).toThrow(/LLM_BASE_URL is required/);
  });
});
