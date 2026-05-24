import { afterEach, beforeEach, describe, expect, it, spyOn } from 'bun:test';
import { installCrashHandlers, startServer } from '../src/main';

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

describe('startServer', () => {
  it('boots the sidecar and serves /healthz', async () => {
    const server = startServer(0); // port 0 → OS picks a free port
    try {
      const res = await fetch(`http://localhost:${server.port}/healthz`);
      expect(res.status).toBe(200);
    } finally {
      server.stop(true);
    }
  });
});

describe('installCrashHandlers', () => {
  it('registers handlers that log unhandled failures', () => {
    const errSpy = spyOn(console, 'error').mockImplementation(() => {});
    const before = {
      rejection: process.listeners('unhandledRejection').slice(),
      exception: process.listeners('uncaughtException').slice(),
    };
    installCrashHandlers();
    const addedRejection = process
      .listeners('unhandledRejection')
      .filter((l) => !before.rejection.includes(l));
    const addedException = process
      .listeners('uncaughtException')
      .filter((l) => !before.exception.includes(l));
    expect(addedRejection).toHaveLength(1);
    expect(addedException).toHaveLength(1);

    // Invoke the handler bodies directly — both the Error and non-Error paths.
    addedRejection[0]?.(new Error('boom'), Promise.resolve());
    addedRejection[0]?.('a string reason', Promise.resolve());
    addedException[0]?.(new Error('fatal'), 'uncaughtException');
    expect(errSpy).toHaveBeenCalled();

    // Clean up so the added handlers don't leak into other tests.
    for (const l of addedRejection) process.off('unhandledRejection', l);
    for (const l of addedException) process.off('uncaughtException', l);
    errSpy.mockRestore();
  });
});
