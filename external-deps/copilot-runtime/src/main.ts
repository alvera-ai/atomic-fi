import { createApp } from './server';
import { log, truncate } from './logger';

const DEFAULT_PORT = 4111;

/** Boot the sidecar on `port` (defaults to `$PORT`, else 4111). Returns the Bun server. */
export function startServer(port: number = Number(process.env.PORT ?? DEFAULT_PORT)) {
  const app = createApp();
  // Bun's default HTTP idle timeout is 10 seconds; SSE streams sit silent
  // during qwen3.5:9b's prompt-eval phase, which trips the timer and the
  // browser surfaces it as ERR_INCOMPLETE_CHUNKED_ENCODING. We bump to
  // 30s — just enough headroom for the 15-second transport-layer SSE
  // keepalive (see `withSseKeepalive` in src/server.ts) to land before
  // Bun decides the socket is dead. Combined, the socket never goes
  // idle for >15s regardless of how long the LLM thinks.
  const server = Bun.serve({ port, fetch: app.fetch, idleTimeout: 30 });
  log.info('server.listening', {
    port: server.port,
    pid: process.pid,
    bun: Bun.version,
    log_level: process.env.LOG_LEVEL ?? 'info',
  });
  return server;
}

/**
 * Surface async failures the request pipeline never sees — an adapter or the
 * runtime rejecting out of band — rather than dying silently.
 */
export function installCrashHandlers(): void {
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

if (import.meta.main) {
  installCrashHandlers();
  startServer();
}
