import { describe, it, expect, beforeAll } from 'vitest';
import supertest from 'supertest';

describe('server', () => {
  beforeAll(() => {
    process.env.OPENAI_API_KEY = 'sk-test';
    process.env.LLM_PROVIDER = 'openai';
  });

  it('GET /healthz returns 200', async () => {
    const { createApp } = await import('../src/server');
    const app = createApp();
    const res = await supertest(app).get('/healthz');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ ok: true, provider: 'openai' });
  });

  it('POST /api/copilotkit responds (LLM call not made — handler mount check)', async () => {
    const { createApp } = await import('../src/server');
    const app = createApp();
    // The handler will attempt to parse the body and route to the adapter;
    // an empty body yields a GraphQL "Must provide query string" error.
    // Yoga returns that as a 200 with an `errors` array (per GraphQL spec)
    // or a 400 depending on accept header — either is fine, just NOT a 5xx
    // crash and NOT a 404 (i.e. the handler IS mounted).
    const res = await supertest(app).post('/api/copilotkit').send({});
    expect(res.status).toBeLessThan(500);
    expect(res.status).not.toBe(404);
  });
});
