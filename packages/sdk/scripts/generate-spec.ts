/**
 * Regenerate `spec/openapi.yaml` from the live OpenApiSpex module via mix.
 *
 *   pnpm --filter @atomic-fi/sdk spec:gen
 *
 * The Elixir source of truth is `lib/atomic_fi_api/api_spec.ex`
 * (`AtomicFiApi.ApiSpec`). The committed YAML here is the reviewable contract
 * — the generated TS SDK derives from it.
 */
import { spawnSync } from 'node:child_process'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const repoRoot = resolve(here, '..', '..', '..')
const out = resolve(here, '..', 'spec', 'openapi.yaml')

const args = [
  'openapi.spec.yaml',
  '--spec',
  'AtomicFiApi.ApiSpec',
  '--start-app=false',
  out,
]

console.log(`→ mix ${args.join(' ')}`)
const r = spawnSync('mix', args, { cwd: repoRoot, stdio: 'inherit' })

if (r.status !== 0) {
  console.error(`✗ mix exited with ${r.status}`)
  process.exit(r.status ?? 1)
}
console.log(`✓ wrote ${out}`)
