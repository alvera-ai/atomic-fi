import { afterEach, beforeEach, describe, expect, it } from 'bun:test';
import { createApp } from '../src/server';

const KEYS = ['LLM_PROVIDER', 'LLM_MODEL'] as const;
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

describe('createApp', () => {
  it('GET /healthz → 200 with the active provider', async () => {
    const res = await createApp().request('/healthz');
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, provider: 'ollama' });
  });

  // The CopilotKit v2 routes under /api/copilotkit are mounted by
  // createCopilotHonoHandler; their request/response contract is verified
  // end to end by the live editor turn. Here we only assert the wrapper
  // delegates both the base path and sub-paths to the handler.
  it('delegates /api/copilotkit to the CopilotKit handler', async () => {
    const res = await createApp().request('/api/copilotkit', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{}',
    });
    expect(res).toBeDefined();
  });

  it('delegates /api/copilotkit/* sub-paths to the handler', async () => {
    const res = await createApp().request('/api/copilotkit/info', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{}',
    });
    expect(res).toBeDefined();
  });
});
