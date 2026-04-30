/**
 * Loads .env.<TARGET_ENV> before any test imports `src/env.ts`.
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
