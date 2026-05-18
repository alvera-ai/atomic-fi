import 'dotenv/config';
import express, { type Express } from 'express';
import { copilotRuntimeNodeExpressEndpoint } from '@copilotkit/runtime';
import { buildRuntime } from './runtime';

export function createApp(): Express {
  const { runtime, serviceAdapter, provider } = buildRuntime();
  const app = express();

  // Mount the CopilotKit endpoint BEFORE express.json() so the underlying
  // yoga server can read the raw request stream itself.
  app.use(
    '/api/copilotkit',
    copilotRuntimeNodeExpressEndpoint({
      endpoint: '/api/copilotkit',
      runtime,
      serviceAdapter,
    }),
  );

  app.use(express.json({ limit: '4mb' }));

  app.get('/healthz', (_req, res) => {
    res.json({ ok: true, provider });
  });

  return app;
}

const PORT = Number(process.env.PORT ?? 4111);
if (import.meta.url === `file://${process.argv[1]}`) {
  createApp().listen(PORT, () => {
    // eslint-disable-next-line no-console
    console.log(`[jdm-copilot-runtime] listening on :${PORT}`);
  });
}
