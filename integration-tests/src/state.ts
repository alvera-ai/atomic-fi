/**
 * Per-runId state directory. One runId per test invocation.
 *
 *   vitest-state/current-runid              — pointer file
 *   vitest-state/<runId>/<spec>.state.json  — per-spec slice (bearer, ids, …)
 *
 * Each spec writes only its own slice. `loadSpec` returns null when missing
 * so specs can short-circuit re-runs via `ctx.skip()`.
 */
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const stateDir = resolve(here, '..', 'vitest-state')
const runIdFile = join(stateDir, 'current-runid')

export function getRunId(): string {
  if (!existsSync(runIdFile)) {
    throw new Error(
      `No runId found at ${runIdFile}. Run "pnpm state:create" before invoking vitest.`,
    )
  }
  return readFileSync(runIdFile, 'utf8').trim()
}

function specPath(runId: string, spec: string): string {
  return join(stateDir, runId, `${spec}.state.json`)
}

export function loadSpec<T = unknown>(spec: string): T | null {
  const path = specPath(getRunId(), spec)
  if (!existsSync(path)) return null
  return JSON.parse(readFileSync(path, 'utf8')) as T
}

export function saveSpec<T>(spec: string, state: T): void {
  const runId = getRunId()
  const dir = join(stateDir, runId)
  mkdirSync(dir, { recursive: true })
  writeFileSync(specPath(runId, spec), JSON.stringify(state, null, 2) + '\n')
}

export type BootstrapState = {
  bearer: string
  bearerExpiresAt: string
  tenantId: string
  tenantSlug: string
  userId: string
  apiKey: string
  apiKeyId: string | null
  roleId: string
  roleName: string
}

export function requireBootstrap(): BootstrapState {
  const s = loadSpec<BootstrapState>('bootstrap')
  if (!s) {
    throw new Error(
      'bootstrap state missing — run tests/bootstrap.test.ts first ' +
        '(it must complete before any other spec).',
    )
  }
  return s
}

// --- Used by scripts/state.ts (CLI). Tests should not call these directly. ---

export function _createRunId(opts: { clean: boolean }): string {
  if (opts.clean && existsSync(stateDir)) {
    for (const entry of readdirSync(stateDir)) {
      rmSync(join(stateDir, entry), { recursive: true, force: true })
    }
  }
  mkdirSync(stateDir, { recursive: true })
  const runId = String(Date.now())
  mkdirSync(join(stateDir, runId), { recursive: true })
  writeFileSync(runIdFile, runId)
  return runId
}

export function _cleanState(): void {
  if (existsSync(stateDir)) rmSync(stateDir, { recursive: true, force: true })
}
