import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));

export const SYSTEM_PROMPT: string = readFileSync(
  join(__dirname, 'system.md'),
  'utf-8',
);
