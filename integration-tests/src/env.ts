/**
 * Environment selection for integration tests.
 *
 * `TARGET_ENV` picks a base URL (`local` | `hh` | `prod`).
 *
 *   - local: credentials come from priv/repo/.bootstrap_creds.json
 *            (written by `mix atomic_fi.dump_bootstrap_creds`).
 *   - hh / prod: credentials come from environment variables, loaded
 *            from .env.<TARGET_ENV> by vitest.setup.ts before this
 *            module is imported.
 *
 * NOTE: dev server runs on :4100 (see config/dev.exs), not :4000.
 */
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const ENVS = {
  local: { baseUrl: 'http://localhost:4100' },
  hh: { baseUrl: 'https://atomicfi-hh.alvera.ai' },
  prod: { baseUrl: 'https://atomicfi.alvera.ai' },
} as const

export type TargetEnv = keyof typeof ENVS

export const targetEnv: TargetEnv =
  (process.env.TARGET_ENV as TargetEnv | undefined) ?? 'local'

if (!(targetEnv in ENVS)) {
  throw new Error(`Unknown TARGET_ENV=${targetEnv} (expected: ${Object.keys(ENVS).join(', ')})`)
}

type BootstrapCreds = {
  tenantSlug: string
  adminEmail: string
  adminPassword: string
  rootApiKey: string
  platformAdminApiKey: string
}

const here = dirname(fileURLToPath(import.meta.url))
const bootstrapCredsPath = resolve(here, '../../priv/repo/.bootstrap_creds.json')

function loadBootstrapCreds(): BootstrapCreds {
  try {
    return JSON.parse(readFileSync(bootstrapCredsPath, 'utf8'))
  } catch (err) {
    throw new Error(
      `Could not read ${bootstrapCredsPath}\n` +
        `Run \`mix atomic_fi.dump_bootstrap_creds\` after \`mix ecto.migrate\`.\n` +
        `Underlying error: ${(err as Error).message}`,
    )
  }
}

function envCreds(): BootstrapCreds {
  const required = ['ADMIN_EMAIL', 'ADMIN_PASSWORD', 'TENANT_SLUG', 'ROOT_API_KEY', 'PLATFORM_ADMIN_API_KEY']
  for (const k of required) {
    if (!process.env[k]) {
      throw new Error(`TARGET_ENV=${targetEnv} requires env var ${k} (set in .env.${targetEnv})`)
    }
  }
  return {
    tenantSlug: process.env.TENANT_SLUG!,
    adminEmail: process.env.ADMIN_EMAIL!,
    adminPassword: process.env.ADMIN_PASSWORD!,
    rootApiKey: process.env.ROOT_API_KEY!,
    platformAdminApiKey: process.env.PLATFORM_ADMIN_API_KEY!,
  }
}

const creds = targetEnv === 'local' ? loadBootstrapCreds() : envCreds()

export const config = {
  targetEnv,
  baseUrl: ENVS[targetEnv].baseUrl,
  tenantSlug: creds.tenantSlug,
  adminEmail: creds.adminEmail,
  adminPassword: creds.adminPassword,
  rootApiKey: creds.rootApiKey,
  platformAdminApiKey: creds.platformAdminApiKey,
} as const
