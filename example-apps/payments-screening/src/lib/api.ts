import type { ApiConfig } from './config'
import type { ScreenResponse } from './types'

export interface ScreenSuccess {
  ok: true
  status: number
  data: ScreenResponse
}
export interface ScreenFailure {
  ok: false
  status: number | null
  error: string
  detail?: unknown
}
export type ScreenResult = ScreenSuccess | ScreenFailure

export interface TenantSummary {
  id: string
  name: string
  slug: string
}

function joinUrl(base: string, path: string): string {
  const trimmed = base.trim().replace(/\/+$/, '')
  return trimmed ? trimmed + path : path
}

// Protected routes authenticate with X-API-Key (M2M). Authorization: Bearer is
// a different path, for human session tokens from POST /api/sessions.
function authHeaders(config: ApiConfig): HeadersInit {
  return {
    'content-type': 'application/json',
    accept: 'application/json',
    'x-api-key': config.apiKey,
  }
}

function describeError(status: number, body: unknown): string {
  const detail =
    body && typeof body === 'object'
      ? ((body as Record<string, unknown>).errors as { detail?: string } | undefined)?.detail
      : undefined
  switch (status) {
    case 401:
      return detail ?? 'Unauthorized — check the API key in Settings.'
    case 403:
      return detail ?? 'Forbidden — this key lacks access to screening.'
    case 422:
      return detail ?? 'The request failed validation. See details below.'
    case 500:
      return detail ?? 'The server errored. The tenant blocklist cache may not be initialized.'
    case 503:
      return detail ?? 'Screening service (Watchman) is unavailable.'
    default:
      return detail ?? `Request failed with status ${status}.`
  }
}

async function parseBody(res: Response): Promise<unknown> {
  const raw = await res.text()
  if (!raw) return null
  try {
    return JSON.parse(raw)
  } catch {
    return raw // non-JSON body (e.g. an HTML error page)
  }
}

/** Resolve the tenant(s) the API key can see. The screening request needs one. */
export async function fetchTenants(
  config: ApiConfig,
): Promise<{ ok: true; tenants: TenantSummary[] } | { ok: false; status: number | null; error: string }> {
  let res: Response
  try {
    res = await fetch(joinUrl(config.baseUrl, '/api/tenants'), { headers: authHeaders(config) })
  } catch (e) {
    return { ok: false, status: null, error: e instanceof Error ? e.message : 'unreachable' }
  }
  const body = await parseBody(res)
  if (!res.ok) return { ok: false, status: res.status, error: describeError(res.status, body) }
  const tenants = ((body as { data?: TenantSummary[] } | null)?.data ?? []) as TenantSummary[]
  return { ok: true, tenants }
}

/** Initialize the tenant's blocklist cache — a prerequisite for screening. */
export async function refreshBlocklistCache(config: ApiConfig): Promise<void> {
  try {
    await fetch(joinUrl(config.baseUrl, '/api/tenants/refresh-blocklist-cache'), {
      method: 'POST',
      headers: authHeaders(config),
    })
  } catch {
    /* best effort — screening will surface the error if the cache is missing */
  }
}

/** POST a preview-screening request and normalize the outcome. */
export async function screen(endpoint: string, body: unknown, config: ApiConfig): Promise<ScreenResult> {
  let res: Response
  try {
    res = await fetch(joinUrl(config.baseUrl, endpoint), {
      method: 'POST',
      headers: authHeaders(config),
      body: JSON.stringify(body),
    })
  } catch (e) {
    const reason = e instanceof Error ? e.message : 'unreachable'
    return { ok: false, status: null, error: `Could not reach the API (${reason}).` }
  }

  const json = await parseBody(res)
  if (!res.ok) {
    return { ok: false, status: res.status, error: describeError(res.status, json), detail: json }
  }
  return { ok: true, status: res.status, data: (json ?? { data: [] }) as ScreenResponse }
}
