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
  const app = new Hono<{ Bindings: NodeBindings }>();

  app.get('/healthz', (c) => c.json({ ok: true, provider }));

  // CopilotKit's Node http endpoint reads + writes the raw Node streams.
  // We hand it `c.env.incoming` and `c.env.outgoing` from @hono/node-server,
  // then return a never-resolving Response so Hono doesn't try to also
  // write to `outgoing`. The endpoint itself terminates the response.
  app.all('/api/copilotkit', async (c) => {
    const handler = copilotRuntimeNodeHttpEndpoint({
      endpoint: '/api/copilotkit',
      runtime,
      serviceAdapter,
    });
    // @hono/node-server exposes the raw Node req/res via `c.env.incoming`
    // and `c.env.outgoing`. The Yoga server adapter's `.handle(req, res)`
    // overload writes directly to the Node response and resolves when done.
    await handler.handle(c.env.incoming, c.env.outgoing);
    return new Response(null, { status: 200 });
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
