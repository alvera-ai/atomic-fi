/**
 * Cross-spec helpers. Each spec is still self-contained — it just imports
 * these utilities so we don't repeat 30 lines of bootstrap per file.
 */
import { config } from './env.ts'

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
export const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/

export type AnyJson = Record<string, unknown>

const jsonHeaders = (extra: Record<string, string> = {}) => ({
  'content-type': 'application/json',
  accept: 'application/json',
  ...extra,
})

export const bearerHeaders = (bearer: string) => jsonHeaders({ authorization: `Bearer ${bearer}` })
export const apiKeyHeaders = (apiKey: string) => jsonHeaders({ 'x-api-key': apiKey })
export const platformAdminHeaders = () => jsonHeaders({ 'x-api-key': config.platformAdminApiKey })

/** POST /api/sessions for the seeded admin and return { bearer, tenantId }. */
export async function postAdminSession(): Promise<{ bearer: string; tenantId: string }> {
  const res = await fetch(`${config.baseUrl}/api/sessions`, {
    method: 'POST',
    headers: jsonHeaders(),
    body: JSON.stringify({
      email: config.adminEmail,
      password: config.adminPassword,
      tenant_slug: config.tenantSlug,
      expires_in: 3600,
    }),
  })
  if (!res.status.toString().startsWith('2')) {
    throw new Error(`session POST → ${res.status}: ${await res.text()}`)
  }
  const body = (await res.json()) as { bearer: string; tenant: { id: string } }
  return { bearer: body.bearer, tenantId: body.tenant.id }
}

/** Best-effort DELETE; swallows network errors so afterAll never blows up. */
export async function safeDelete(path: string, headers: Record<string, string>): Promise<void> {
  await fetch(`${config.baseUrl}${path}`, { method: 'DELETE', headers }).catch(() => {})
}

/** Convenience: pass the path-tail and bearer to GET a JSON resource. */
export async function getJson<T = AnyJson>(
  path: string,
  headers: Record<string, string>,
): Promise<{ status: number; body: T }> {
  const res = await fetch(`${config.baseUrl}${path}`, { headers })
  return { status: res.status, body: (await res.json()) as T }
}
