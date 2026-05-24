import { afterEach, beforeEach, describe, expect, it, spyOn } from 'bun:test';
import { formatValue, log, truncate } from '../src/logger';

describe('formatValue', () => {
  it('renders each value kind', () => {
    expect(formatValue(null)).toBe('null');
    expect(formatValue(undefined)).toBe('undefined');
    expect(formatValue('')).toBe('""');
    expect(formatValue('plain')).toBe('plain');
    expect(formatValue('two words')).toBe('"two words"');
    expect(formatValue('a=b')).toBe('"a=b"');
    expect(formatValue(42)).toBe('42');
    expect(formatValue(true)).toBe('true');
    expect(formatValue({ a: 1 })).toBe('{"a":1}');
  });

  it('falls back to String() when JSON.stringify throws', () => {
    const circular: Record<string, unknown> = {};
    circular.self = circular;
    expect(formatValue(circular)).toContain('object');
  });
});

describe('truncate', () => {
  it('returns null for null / undefined', () => {
    expect(truncate(null)).toBeNull();
    expect(truncate(undefined)).toBeNull();
  });

  it('keeps short strings, clips long ones', () => {
    expect(truncate('short')).toBe('short');
    expect(truncate('x'.repeat(50), 10)).toBe(`${'x'.repeat(10)}…(+40 chars)`);
  });
});

describe('log', () => {
  let out: string[];
  let err: string[];
  let logSpy: ReturnType<typeof spyOn>;
  let errSpy: ReturnType<typeof spyOn>;

  beforeEach(() => {
    out = [];
    err = [];
    logSpy = spyOn(console, 'log').mockImplementation((line: unknown) => {
      out.push(String(line));
    });
    errSpy = spyOn(console, 'error').mockImplementation((line: unknown) => {
      err.push(String(line));
    });
  });

  afterEach(() => {
    logSpy.mockRestore();
    errSpy.mockRestore();
    delete process.env.LOG_LEVEL;
  });

  it('writes info / warn to stdout, error to stderr', () => {
    log.info('e.info', { k: 'v' });
    log.warn('e.warn');
    log.error('e.error');
    expect(out.some((l) => l.includes('e.info') && l.includes('k=v'))).toBe(true);
    expect(out.some((l) => l.includes('e.warn'))).toBe(true);
    expect(err.some((l) => l.includes('e.error'))).toBe(true);
  });

  it('suppresses debug unless LOG_LEVEL=debug', () => {
    log.debug('e.hidden');
    expect(out.some((l) => l.includes('e.hidden'))).toBe(false);
    process.env.LOG_LEVEL = 'debug';
    log.debug('e.shown');
    expect(out.some((l) => l.includes('e.shown'))).toBe(true);
  });
});
