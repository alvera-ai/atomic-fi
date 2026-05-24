import { afterEach, beforeEach, describe, expect, it } from 'bun:test';
import { aisdkFactory, buildRuntime } from '../src/runtime';

const KEYS = ['LLM_PROVIDER', 'LLM_MODEL', 'OLLAMA_BASE_URL'] as const;
const saved: Record<string, string | undefined> = {};

beforeEach(() => {
  for (const k of KEYS) saved[k] = process.env[k];
  process.env.LLM_PROVIDER = 'ollama';
  process.env.LLM_MODEL = 'qwen3.5:9b';
});

afterEach(() => {
  for (const k of KEYS) {
    if (saved[k] === undefined) delete process.env[k];
    else process.env[k] = saved[k];
  }
});

describe('buildRuntime', () => {
  it('builds a v2 CopilotRuntime', () => {
    expect(buildRuntime()).toBeDefined();
  });
});

describe('aisdkFactory', () => {
  it('runs a turn and returns a streamed result', () => {
    const controller = new AbortController();
    const ctx = {
      input: {
        messages: [{ id: 'm1', role: 'user', content: 'add an expression node' }],
        tools: [],
      },
      abortController: controller,
      abortSignal: controller.signal,
    };
    // streamText is lazy — constructing the result does not hit the network.
    const result = aisdkFactory(ctx as unknown as Parameters<typeof aisdkFactory>[0]);
    expect(result).toHaveProperty('fullStream');
  });
});
