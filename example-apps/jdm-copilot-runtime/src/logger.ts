// Structured logger for the sidecar. Designed to be tail-friendly: each line is
// `ISO-timestamp [LEVEL] event-name k1=v1 k2=v2` so you can grep by event or
// pipe through `jq`-style tools after a tiny transform. No external dep.

type Level = 'INFO' | 'WARN' | 'ERROR' | 'DEBUG';
type Fields = Record<string, unknown>;

const DEBUG = process.env.LOG_LEVEL === 'debug';

function formatValue(v: unknown): string {
  if (v === null) return 'null';
  if (v === undefined) return 'undefined';
  if (typeof v === 'string') {
    // Quote strings that contain whitespace or '=' so the line stays parseable.
    if (v.length === 0) return '""';
    if (/\s|=/.test(v)) return JSON.stringify(v);
    return v;
  }
  if (typeof v === 'number' || typeof v === 'boolean') return String(v);
  // Objects/arrays: compact JSON, single line.
  try {
    return JSON.stringify(v);
  } catch {
    return String(v);
  }
}

function emit(level: Level, event: string, fields?: Fields): void {
  if (level === 'DEBUG' && !DEBUG) return;
  const ts = new Date().toISOString();
  const parts = [`${ts} [${level.padEnd(5)}] ${event}`];
  if (fields && Object.keys(fields).length > 0) {
    for (const [k, v] of Object.entries(fields)) {
      parts.push(`${k}=${formatValue(v)}`);
    }
  }
  const line = parts.join(' ');
  // eslint-disable-next-line no-console
  if (level === 'ERROR') console.error(line);
  // eslint-disable-next-line no-console
  else console.log(line);
}

export const log = {
  info: (event: string, fields?: Fields) => emit('INFO', event, fields),
  warn: (event: string, fields?: Fields) => emit('WARN', event, fields),
  error: (event: string, fields?: Fields) => emit('ERROR', event, fields),
  debug: (event: string, fields?: Fields) => emit('DEBUG', event, fields),
};

// Truncate long strings for log readability while preserving the start (which
// is usually the most informative part — user messages, error first lines).
export function truncate(s: string | undefined | null, max = 200): string | null {
  if (s == null) return null;
  if (s.length <= max) return s;
  return s.slice(0, max) + `…(+${s.length - max} chars)`;
}
