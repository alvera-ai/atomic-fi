/**
 * Keeps @atomic-fi/sdk package.json `version` in sync with mix.exs.
 *
 *   pnpm version:sync   — rewrites package.json version to match mix.exs
 *   pnpm version:check  — exits non-zero if they differ (CI-friendly)
 */
import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const repoRoot = resolve(here, '..', '..', '..')
const mixPath = join(repoRoot, 'mix.exs')
const pkgPath = resolve(here, '..', 'package.json')

const mix = readFileSync(mixPath, 'utf8')
const m = mix.match(/^\s*version:\s*"([^"]+)"/m)
if (!m) {
  console.error(`Could not find version: "..." in ${mixPath}`)
  process.exit(2)
}
const mixVersion = m[1]

const pkg = JSON.parse(readFileSync(pkgPath, 'utf8'))
const pkgVersion = pkg.version

if (pkgVersion === mixVersion) {
  console.log(`✓ in sync: ${mixVersion}`)
  process.exit(0)
}

if (process.argv.includes('--check')) {
  console.error(`✗ version mismatch: mix.exs=${mixVersion} package.json=${pkgVersion}`)
  console.error('  fix: pnpm --filter @atomic-fi/sdk version:sync')
  process.exit(1)
}

pkg.version = mixVersion
writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + '\n')
console.log(`✓ package.json bumped: ${pkgVersion} → ${mixVersion}`)
