/**
 * bootstrap — first spec to run; mints a bearer for the rest of the suite
 * and verifies BOTH auth transports work end-to-end against the seeded
 * system tenant.
 *
 * What it asserts (insights from manual curl, captured in code):
 *
 *   POST /api/sessions
 *     - 201 Created
 *     - returns { bearer, expires_at, tenant, role, user, type: "user", api_key_id: null }
 *     - bearer is a non-empty string (token format unspecified — opaque)
 *
 *   GET /api/sessions/verify (Bearer)
 *     - 200 OK
 *     - type === "user", user populated (email + id), api_key_id === null
 *     - api_key field is absent
 *     - expires_at matches the session
 *
 *   GET /api/sessions/verify (x-api-key)
 *     - 200 OK
 *     - type === "api", api_key populated + api_key_id is a UUID
 *     - user field is OMITTED from the response (NOT set to null —
 *       Phoenix view simply doesn't render it)
 *     - expires_at === null  (API keys do not expire by default)
 *
 *   GET /api/sessions/verify (no auth)
 *     - 401 with "Credentials required" detail
 *
 * Persisted to vitest-state/<runId>/bootstrap.state.json so resource specs
 * can pick up bearer + tenantId without signing in again.
 */
import { describe, expect, it } from 'vitest'

import { config } from '../../src/env.ts'
import { buildApiKeySdk, buildBearerSdk } from '../../src/sdk.ts'
import { loadSpec, saveSpec, type BootstrapState } from '../../src/state.ts'

const SPEC = 'bootstrap'
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

type SessionResponse = {
  bearer?: string
  expires_at: string | null
  active: boolean
  type: 'user' | 'api'
  api_key_id: string | null
  api_key?: { id: string; name: string }
  tenant: { id: string; slug: string; name: string }
  role: { id: string; name: string }
  user?: { id: string; email: string }
}

describe('e2e/bootstrap', () => {
  let s = loadSpec<BootstrapState>(SPEC) ?? ({} as Partial<BootstrapState>)

  it('POST /api/sessions returns a bearer for the seeded admin', async (ctx) => {
    if (s.bearer) {
      ctx.skip()
      return
    }

    const res = await fetch(`${config.baseUrl}/api/sessions`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify({
        email: config.rootEmail,
        password: config.rootPassword,
        tenant_slug: config.rootTenantSlug,
        // Long enough that re-running specs in the same runId always finds a
        // valid bearer; specs intentionally exercising expiry should mint
        // their own short-lived session.
        expires_in: 3600,
      }),
    })

    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as SessionResponse

    expect(body.type).toBe('user')
    expect(body.active).toBe(true)
    expect(body.api_key_id).toBeNull()
    expect(body.bearer).toEqual(expect.any(String))
    expect(body.bearer!.length).toBeGreaterThan(8)
    expect(body.tenant.slug).toBe(config.rootTenantSlug)
    expect(body.tenant.id).toMatch(UUID_RE)
    expect(body.role.name).toBe('root')
    expect(body.user!.email).toBe(config.rootEmail)
    expect(body.user!.id).toMatch(UUID_RE)
    expect(body.expires_at).toEqual(expect.any(String))

    s = {
      ...(s as object),
      bearer: body.bearer!,
      bearerExpiresAt: body.expires_at!,
      tenantId: body.tenant.id,
      tenantSlug: body.tenant.slug,
      userId: body.user!.id,
      apiKey: config.rootApiKey,
      apiKeyId: null,
      roleId: body.role.id,
      roleName: body.role.name,
    } as BootstrapState
    saveSpec(SPEC, s)
  })

  it('GET /api/sessions/verify with Bearer returns a user-typed session', async () => {
    expect(s.bearer, 'previous step must have set bearer').toBeTruthy()
    const sdk = buildBearerSdk(s.bearer!)

    const res = await fetch(`${config.baseUrl}/api/sessions/verify`, {
      headers: { authorization: `Bearer ${s.bearer}`, accept: 'application/json' },
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as SessionResponse

    expect(body.type).toBe('user')
    expect(body.active).toBe(true)
    expect(body.api_key_id).toBeNull()
    expect(body.user!.email).toBe(config.rootEmail)
    expect(body.tenant.slug).toBe(config.rootTenantSlug)
    expect(body.role.name).toBe('root')
    expect(body.expires_at).toBe(s.bearerExpiresAt)

    // Sanity: SDK builder produces the right config for downstream specs.
    expect(sdk).toBeDefined()
  })

  it('GET /api/sessions/verify with x-api-key returns an api-typed session', async () => {
    const sdk = buildApiKeySdk(config.rootApiKey)

    const res = await fetch(`${config.baseUrl}/api/sessions/verify`, {
      headers: { 'x-api-key': config.rootApiKey, accept: 'application/json' },
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as SessionResponse

    expect(body.type).toBe('api')
    expect(body.active).toBe(true)
    // user is OMITTED from API-key sessions (the view does not render it).
    expect(body.user).toBeUndefined()
    expect(body.api_key_id).toMatch(UUID_RE)
    expect(body.api_key?.id).toBe(body.api_key_id)
    // API keys don't expire by default.
    expect(body.expires_at).toBeNull()
    expect(body.tenant.slug).toBe(config.rootTenantSlug)
    expect(body.role.name).toBe('root')

    s.apiKeyId = body.api_key_id
    saveSpec(SPEC, s as BootstrapState)

    expect(sdk).toBeDefined()
  })

  it('GET /api/sessions/verify with no auth returns 401', async () => {
    const res = await fetch(`${config.baseUrl}/api/sessions/verify`, {
      headers: { accept: 'application/json' },
    })
    expect(res.status).toBe(401)
    const body = (await res.json()) as { errors: { detail: string } }
    expect(body.errors.detail).toMatch(/credentials required/i)
  })

  it('GET /api/sessions/verify with bad x-api-key returns 401', async () => {
    const res = await fetch(`${config.baseUrl}/api/sessions/verify`, {
      headers: { 'x-api-key': 'totally-bogus', accept: 'application/json' },
    })
    expect(res.status).toBe(401)
    const body = (await res.json()) as { errors: { detail: string } }
    expect(body.errors.detail).toMatch(/invalid api key/i)
  })
})
