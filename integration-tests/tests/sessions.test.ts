/**
 * sessions — extension cases for /api/sessions beyond the bootstrap.
 *
 * bootstrap.test.ts already covers create-bearer + verify-bearer +
 * verify-api-key + 401s. This spec adds:
 *   - DELETE /api/sessions revokes the bearer
 *   - GET /api/sessions/verify with revoked bearer → 401
 *   - POST /api/sessions with bad password → 401
 *   - POST /api/sessions with bad tenant_slug → 401/404
 *   - POST /api/sessions custom expires_in echoes back
 */
import { describe, expect, it } from 'vitest'

import { config } from '../src/env.ts'

type AnyJson = Record<string, unknown>

async function postSession(body: AnyJson): Promise<Response> {
  return fetch(`${config.baseUrl}/api/sessions`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify(body),
  })
}

describe('sessions — /api/sessions (extension)', () => {
  it('POST /api/sessions custom expires_in is honored', async () => {
    const res = await postSession({
      email: config.adminEmail,
      password: config.adminPassword,
      tenant_slug: config.tenantSlug,
      expires_in: 300,
    })
    expect(res.status).toBe(201)
    const body = (await res.json()) as AnyJson
    const expiresAt = new Date(body.expires_at as string).getTime()
    const now = Date.now()
    // Within 60s of "now + 300s" — generous to absorb clock skew + RTT.
    expect(Math.abs(expiresAt - (now + 300_000))).toBeLessThan(60_000)
  })

  it('POST /api/sessions wrong password → 401', async () => {
    const res = await postSession({
      email: config.adminEmail,
      password: 'definitely-not-the-password',
      tenant_slug: config.tenantSlug,
    })
    expect(res.status).toBe(401)
  })

  it('POST /api/sessions unknown tenant_slug → 401/404', async () => {
    const res = await postSession({
      email: config.adminEmail,
      password: config.adminPassword,
      tenant_slug: 'no-such-tenant-slug-here',
    })
    // Implementation may collapse "tenant not found" into 401 to avoid
    // leaking tenant existence; either is acceptable.
    expect([401, 404]).toContain(res.status)
  })

  it('DELETE /api/sessions revokes the bearer; subsequent verify → 401', async () => {
    const create = await postSession({
      email: config.adminEmail,
      password: config.adminPassword,
      tenant_slug: config.tenantSlug,
      expires_in: 600,
    })
    expect(create.status).toBe(201)
    const { bearer } = (await create.json()) as { bearer: string }

    // Verify the new bearer works
    const verifyOk = await fetch(`${config.baseUrl}/api/sessions/verify`, {
      headers: { authorization: `Bearer ${bearer}`, accept: 'application/json' },
    })
    expect(verifyOk.status).toBe(200)

    // Revoke
    const del = await fetch(`${config.baseUrl}/api/sessions`, {
      method: 'DELETE',
      headers: { authorization: `Bearer ${bearer}`, accept: 'application/json' },
    })
    expect(del.status).toBe(204)

    // Subsequent verify is rejected
    const verifyFail = await fetch(`${config.baseUrl}/api/sessions/verify`, {
      headers: { authorization: `Bearer ${bearer}`, accept: 'application/json' },
    })
    expect(verifyFail.status).toBe(401)
  })
})
