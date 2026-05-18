import { describe, it, expect, beforeAll } from 'vitest';

describe('server', () => {
  beforeAll(() => {
    process.env.OPENAI_API_KEY = 'sk-test';
    process.env.LLM_PROVIDER = 'openai';
  });

  it('GET /healthz returns 200 with provider', async () => {
    const { createApp } = await import('../src/server');
    const app = createApp();
    const res = await app.request('/healthz');
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, provider: 'openai' });
  });

  it('POST /api/copilotkit is mounted (does not 404)', async () => {
    const { createApp } = await import('../src/server');
    const app = createApp();
    const res = await app.request('/api/copilotkit', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({}),
    });
    // 404 means the route isn't registered; we only verify mount, not behavior.
    // (Real Node-http bridging is exercised by the dev server, not by app.request,
    // because app.request bypasses @hono/node-server and so c.env.incoming is undefined.)
    expect(res.status).not.toBe(404);
  });
});
