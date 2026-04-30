/**
 * Environment selection for integration tests.
 *
 * `TARGET_ENV` picks a base URL (`local` | `hh` | `prod`).
 * Credentials come from `.env.<TARGET_ENV>` via dotenv (loaded in vitest.setup.ts).
 *
 * NOTE: dev server runs on :4100 (see config/dev.exs), not :4000.
 */

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

export const config = {
  targetEnv,
  baseUrl: ENVS[targetEnv].baseUrl,
  rootEmail: process.env.ROOT_EMAIL ?? 'admin@atomic-fi.local',
  rootPassword: process.env.ROOT_PASSWORD ?? 'admin-password-dev',
  rootTenantSlug: process.env.ROOT_TENANT_SLUG ?? 'atomic-fi-tenant',
  rootApiKey: process.env.ROOT_API_KEY ?? 'alvera_root_api_key_dev',
} as const
