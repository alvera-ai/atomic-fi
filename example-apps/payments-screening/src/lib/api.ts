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

function joinUrl(base: string, path: string): string {
  const trimmed = base.trim().replace(/\/+$/, '')
  return trimmed ? trimmed + path : path
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
    case 503:
      return detail ?? 'Screening service (Watchman) is unavailable.'
    default:
      return detail ?? `Request failed with status ${status}.`
  }
}

/** POST a preview-screening request and normalize the outcome. */
export async function screen(
  endpoint: string,
  body: unknown,
  config: ApiConfig,
): Promise<ScreenResult> {
  let res: Response
  try {
    res = await fetch(joinUrl(config.baseUrl, endpoint), {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        accept: 'application/json',
        authorization: `Bearer ${config.apiKey}`,
      },
      body: JSON.stringify(body),
    })
  } catch (e) {
    const reason = e instanceof Error ? e.message : 'unreachable'
    return { ok: false, status: null, error: `Could not reach the API (${reason}).` }
  }

  const raw = await res.text()
  let json: unknown = null
  try {
    json = raw ? JSON.parse(raw) : null
  } catch {
    json = raw // non-JSON body (e.g. an HTML error page) — keep as the detail
  }

  if (!res.ok) {
    return { ok: false, status: res.status, error: describeError(res.status, json), detail: json }
  }
  return { ok: true, status: res.status, data: (json ?? { data: [] }) as ScreenResponse }
}
