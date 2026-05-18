import 'dotenv/config';
import { Hono } from 'hono';
import { serve } from '@hono/node-server';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { copilotRuntimeNodeHttpEndpoint } from '@copilotkit/runtime';
import { buildRuntime } from './runtime';

type NodeBindings = {
  incoming: IncomingMessage;
  outgoing: ServerResponse;
};

export function createApp(): Hono<{ Bindings: NodeBindings }> {
  const { runtime, serviceAdapter, provider } = buildRuntime();
  // Build the Yoga-backed Node http handler once per app instance, not per
  // request — the factory does non-trivial setup (graphql schema, plugins).
  const handler = copilotRuntimeNodeHttpEndpoint({
    endpoint: '/api/copilotkit',
    runtime,
    serviceAdapter,
  });
  const app = new Hono<{ Bindings: NodeBindings }>();

  app.get('/healthz', (c) => c.json({ ok: true, provider }));

  // CopilotKit's Node http endpoint reads + writes the raw Node streams.
  // We hand it `c.env.incoming` and `c.env.outgoing` from @hono/node-server,
  // then return a Response carrying the `x-hono-already-sent` sentinel so
  // @hono/node-server's listener skips its own writeHead/end — the Yoga
  // handler has already finished writing to `outgoing` (including SSE chunks
  // for streaming chat completions).
  app.all('/api/copilotkit', async (c) => {
    await handler.handle(c.env.incoming, c.env.outgoing);
    return new Response(null, { headers: { 'x-hono-already-sent': 'true' } });
  });

  return app;
}

const PORT = Number(process.env.PORT ?? 4111);
if (import.meta.url === `file://${process.argv[1]}`) {
  serve({ fetch: createApp().fetch, port: PORT }, (info) => {
    // eslint-disable-next-line no-console
    console.log(`[jdm-copilot-runtime] listening on :${info.port}`);
  });
}
