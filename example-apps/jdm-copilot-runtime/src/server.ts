import { config as loadEnv } from 'dotenv';
loadEnv({ path: '.env.local' });
loadEnv();
import { Hono } from 'hono';
import { serve } from '@hono/node-server';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { copilotRuntimeNodeHttpEndpoint } from '@copilotkit/runtime';
import { buildRuntime } from './runtime';
import { log, truncate } from './logger';

type NodeBindings = {
  incoming: IncomingMessage;
  outgoing: ServerResponse;
};

let requestSeq = 0;

export function createApp(): Hono<{ Bindings: NodeBindings }> {
  const { runtime, serviceAdapter, provider } = buildRuntime();
  log.info('runtime.built', {
    provider,
    model: process.env.LLM_MODEL ?? '(adapter default)',
  });

  // Build the Yoga-backed Node http handler once per app instance, not per
  // request — the factory does non-trivial setup (graphql schema, plugins).
  const handler = copilotRuntimeNodeHttpEndpoint({
    endpoint: '/api/copilotkit',
    runtime,
    serviceAdapter,
  });
  const app = new Hono<{ Bindings: NodeBindings }>();

  // Global request/response logger. Logs every inbound HTTP call, the
  // outbound status + duration, and any error thrown by a downstream handler.
  app.use('*', async (c, next) => {
    const reqId = `req-${++requestSeq}`;
    const start = Date.now();
    log.info('http.request', {
      req_id: reqId,
      method: c.req.method,
      path: c.req.path,
      content_length: c.req.header('content-length') ?? '0',
      content_type: c.req.header('content-type') ?? '(none)',
    });
    try {
      await next();
      log.info('http.response', {
        req_id: reqId,
        method: c.req.method,
        path: c.req.path,
        status: c.res.status,
        duration_ms: Date.now() - start,
      });
    } catch (err) {
      log.error('http.exception', {
        req_id: reqId,
        method: c.req.method,
        path: c.req.path,
        duration_ms: Date.now() - start,
        error: err instanceof Error ? err.message : String(err),
        stack: truncate(err instanceof Error ? err.stack : null, 800),
      });
      throw err;
    }
  });

  app.get('/healthz', (c) => c.json({ ok: true, provider }));

  // CopilotKit's Node http endpoint reads + writes the raw Node streams.
  // We hand it `c.env.incoming` and `c.env.outgoing` from @hono/node-server,
  // then return a Response carrying the `x-hono-already-sent` sentinel so
  // @hono/node-server's listener skips its own writeHead/end — the Yoga
  // handler has already finished writing to `outgoing` (including SSE chunks
  // for streaming chat completions).
  app.all('/api/copilotkit', async (c) => {
    try {
      await handler.handle(c.env.incoming, c.env.outgoing);
    } catch (err) {
      log.error('copilotkit.handler.exception', {
        method: c.req.method,
        path: c.req.path,
        error: err instanceof Error ? err.message : String(err),
        stack: truncate(err instanceof Error ? err.stack : null, 800),
      });
      throw err;
    }
    return new Response(null, { headers: { 'x-hono-already-sent': 'true' } });
  });

  // Hono-level error fallback for anything that escapes the middleware
  // try/catch above (e.g. errors thrown during route matching itself).
  app.onError((err, c) => {
    log.error('hono.onError', {
      method: c.req.method,
      path: c.req.path,
      error: err instanceof Error ? err.message : String(err),
      stack: truncate(err instanceof Error ? err.stack : null, 800),
    });
    return c.text('Internal Server Error', 500);
  });

  return app;
}

const PORT = Number(process.env.PORT ?? 4111);
if (import.meta.url === `file://${process.argv[1]}`) {
  serve({ fetch: createApp().fetch, port: PORT }, (info) => {
    log.info('server.listening', {
      port: info.port,
      pid: process.pid,
      node: process.version,
      log_level: process.env.LOG_LEVEL ?? 'info',
    });
  });

  // Crash-safety logging: an unhandled rejection here usually means the Yoga
  // handler or an adapter threw asynchronously without our middleware seeing
  // it. Worth surfacing rather than letting the process die silently.
  process.on('unhandledRejection', (reason) => {
    log.error('process.unhandledRejection', {
      reason: reason instanceof Error ? reason.message : String(reason),
      stack: truncate(reason instanceof Error ? reason.stack : null, 800),
    });
  });
  process.on('uncaughtException', (err) => {
    log.error('process.uncaughtException', {
      error: err.message,
      stack: truncate(err.stack, 800),
    });
  });
}
