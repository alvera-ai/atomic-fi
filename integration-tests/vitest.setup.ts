/**
 * Loads .env.<TARGET_ENV> before any test imports `src/env.ts`.
 *
 * No global authentication or DB reset here — each spec is self-contained
 * and authenticates in its own beforeAll. vitest.setup.ts is intentionally
 * minimal: just put the right env vars on process.env so src/env.ts can
 * pick them up.
 */
import { config as loadDotenv } from 'dotenv'
import { existsSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const envName = process.env.TARGET_ENV ?? 'local'
const envFile = resolve(here, `.env.${envName}`)

if (existsSync(envFile)) {
  loadDotenv({ path: envFile })
}
