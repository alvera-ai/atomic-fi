import { Hono } from 'hono';
import { createCopilotHonoHandler } from '@copilotkit/runtime/v2/hono';
import { buildRuntime } from './runtime';
import { envProvider } from './models/index';
import { log } from './logger';

/** The path the calling CopilotKit client posts to. */
const COPILOT_BASE_PATH = '/api/copilotkit';

/**
 * Build the Hono app: a `/healthz` probe plus the CopilotKit v2 runtime
 * served at `/api/copilotkit`.
 *
 * `/healthz` is registered first on our own Hono app, then every
 * `/api/copilotkit` request is delegated to the handler that
 * `createCopilotHonoHandler` builds. (Routes can't be appended to that
 * handler after the fact — its own routes match first — so we wrap it.)
 * The handler manages CORS itself (all origins, no credentials, by default).
 *
 * Pure factory: no port binding. `src/main.ts` owns the entrypoint, which
 * keeps this unit-testable via `app.request(...)`.
 */
export function createApp(): Hono {
  const provider = envProvider();
  const runtime = buildRuntime();
  log.info('runtime.built', { provider, model: process.env.LLM_MODEL ?? '(unset)' });

  const copilot = createCopilotHonoHandler({ runtime, basePath: COPILOT_BASE_PATH });

  const app = new Hono();
  app.get('/healthz', (c) => c.json({ ok: true, provider }));
  app.all(COPILOT_BASE_PATH, (c) => copilot.fetch(c.req.raw));
  app.all(`${COPILOT_BASE_PATH}/*`, (c) => copilot.fetch(c.req.raw));
  return app;
}
