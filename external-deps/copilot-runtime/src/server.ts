import { Hono } from 'hono';
import { createCopilotHonoHandler } from '@copilotkit/runtime/v2/hono';
import { buildRuntime } from './runtime';
import { envProvider } from './models/index';
import { log } from './logger';

/** The path the calling CopilotKit client posts to. */
const COPILOT_BASE_PATH = '/api/copilotkit';

/** SSE keepalive interval — must be < `Bun.serve.idleTimeout` (30s). */
const SSE_KEEPALIVE_MS = 15_000;

/**
 * Transport-level SSE keepalive. CopilotKit's BuiltInAgent in Factory Mode
 * emits no AG-UI events during the LLM's prompt-eval window — the socket
 * sits silent until the first token. Bun's default idleTimeout (10s) and
 * many intermediate proxies kill silent sockets long before that — the
 * browser surfaces it as `ERR_INCOMPLETE_CHUNKED_ENCODING`.
 *
 * The canonical SSE keepalive is a comment frame (`: <anything>\n\n`).
 * Clients are required to ignore comment lines, so this is a transport-
 * level no-op visible only as bytes flowing — exactly what every idle
 * timer in the network path needs to see. Independent of, and orthogonal
 * to, CopilotKit's own ACTIVITY_SNAPSHOT heartbeats (which are protocol-
 * level events the chat UI may render). We use the byte-level frame
 * because Factory Mode doesn't give us a seam to inject protocol events.
 */
async function withSseKeepalive(response: Response, intervalMs: number = SSE_KEEPALIVE_MS): Promise<Response> {
  const contentType = response.headers.get('content-type') ?? '';
  if (!contentType.startsWith('text/event-stream')) return response;
  if (!response.body) return response;

  const upstream = response.body.getReader();
  const encoder = new TextEncoder();
  const keepaliveFrame = encoder.encode(': keepalive\n\n');

  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      let closed = false;
      let lastByteAt = Date.now();

      const timer = setInterval(() => {
        if (closed) return;
        if (Date.now() - lastByteAt < intervalMs) return;
        try {
          controller.enqueue(keepaliveFrame);
          lastByteAt = Date.now();
        } catch {
          // Controller already closed — drop the keepalive.
        }
      }, Math.max(1_000, Math.floor(intervalMs / 2)));

      const pump = async (): Promise<void> => {
        try {
          while (true) {
            const { value, done } = await upstream.read();
            if (done) break;
            lastByteAt = Date.now();
            controller.enqueue(value);
          }
        } catch (err) {
          // Upstream errored — propagate, close cleanly.
          controller.error(err);
        } finally {
          closed = true;
          clearInterval(timer);
          try {
            controller.close();
          } catch {
            // Already closed.
          }
        }
      };

      pump();
    },
    cancel(reason) {
      upstream.cancel(reason).catch(() => {
        // Best-effort cleanup; upstream may already be cancelled.
      });
    },
  });

  return new Response(stream, {
    status: response.status,
    statusText: response.statusText,
    headers: response.headers,
  });
}

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
  app.all(COPILOT_BASE_PATH, async (c) => withSseKeepalive(await copilot.fetch(c.req.raw)));
  app.all(`${COPILOT_BASE_PATH}/*`, async (c) => withSseKeepalive(await copilot.fetch(c.req.raw)));
  return app;
}
