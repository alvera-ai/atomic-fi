// Structured, tail-friendly logger: one line per event —
// `ISO-timestamp [LEVEL] event key=value …`. No dependency.

type Level = 'INFO' | 'WARN' | 'ERROR' | 'DEBUG';
type Fields = Record<string, unknown>;

// Read per-call (not a module constant) so tests can toggle LOG_LEVEL.
const debugEnabled = (): boolean => process.env.LOG_LEVEL === 'debug';

/** Render one field value as a single, grep-friendly token. */
export function formatValue(value: unknown): string {
  if (value === null) return 'null';
  if (value === undefined) return 'undefined';
  if (typeof value === 'string') {
    if (value.length === 0) return '""';
    // Quote strings with whitespace or '=' so the line stays parseable.
    return /\s|=/.test(value) ? JSON.stringify(value) : value;
  }
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function emit(level: Level, event: string, fields?: Fields): void {
  if (level === 'DEBUG' && !debugEnabled()) return;
  const parts = [`${new Date().toISOString()} [${level.padEnd(5)}] ${event}`];
  for (const [key, value] of Object.entries(fields ?? {})) {
    parts.push(`${key}=${formatValue(value)}`);
  }
  const line = parts.join(' ');
  if (level === 'ERROR') console.error(line);
  else console.log(line);
}

export const log = {
  info: (event: string, fields?: Fields) => emit('INFO', event, fields),
  warn: (event: string, fields?: Fields) => emit('WARN', event, fields),
  error: (event: string, fields?: Fields) => emit('ERROR', event, fields),
  debug: (event: string, fields?: Fields) => emit('DEBUG', event, fields),
};

/** Clip a long string, keeping the (most informative) head. */
export function truncate(text: string | null | undefined, max = 200): string | null {
  if (text == null) return null;
  return text.length <= max ? text : `${text.slice(0, max)}…(+${text.length - max} chars)`;
}
