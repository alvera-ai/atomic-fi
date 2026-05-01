/**
 * api_keys — full CRUD + RLS coverage for /api/api-keys.
 *
 * Each api_key needs a role; we create a one-off role in the primary tenant
 * during beforeAll, and clean it up in afterAll.
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest'

import { mintSecondaryTenant, type SecondaryTenant } from '@atomic-fi/sdk'

import { config } from '../src/env.ts'

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

type AnyJson = Record<string, unknown>

async function postSession(): Promise<{ bearer: string; tenantId: string }> {
  const res = await fetch(`${config.baseUrl}/api/sessions`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', accept: 'application/json' },
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

const json = (extra: Record<string, string> = {}) => ({
  'content-type': 'application/json',
  accept: 'application/json',
  ...extra,
})
const bearerHeaders = (b: string) => json({ authorization: `Bearer ${b}` })
const apiKeyHeaders = (k: string) => json({ 'x-api-key': k })

describe('api_keys — /api/api-keys', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let roleId: string
  let apiKeyId: string
  const suffix = String(Date.now())
  const uniqueRoleName = `api_keys_role_${suffix}`
  const uniqueKeyName = `api-keys-spec-${suffix}`

  beforeAll(async () => {
    const session = await postSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId

    const roleRes = await fetch(`${config.baseUrl}/api/roles`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        name: uniqueRoleName,
        description: 'role for api_keys spec',
        metadata: {},
        tenant_id: primaryTenantId,
      }),
    })
    if (!roleRes.ok) {
      throw new Error(`api_keys beforeAll: role create → ${roleRes.status}: ${await roleRes.text()}`)
    }
    roleId = ((await roleRes.json()) as { id: string }).id

    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-api-keys',
    })
  })

  afterAll(async () => {
    if (apiKeyId) {
      await fetch(`${config.baseUrl}/api/api-keys/${apiKeyId}`, {
        method: 'DELETE',
        headers: bearerHeaders(bearer),
      }).catch(() => {})
    }
    if (roleId) {
      await fetch(`${config.baseUrl}/api/roles/${roleId}`, {
        method: 'DELETE',
        headers: bearerHeaders(bearer),
      }).catch(() => {})
    }
  })

  it('POST /api/api-keys → 201 returns raw_key', async () => {
    const res = await fetch(`${config.baseUrl}/api/api-keys`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        name: uniqueKeyName,
        tenant_id: primaryTenantId,
        role_id: roleId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.name).toBe(uniqueKeyName)
    expect(body.tenant_id).toBe(primaryTenantId)
    expect(body.role_id).toBe(roleId)
    expect(body.raw_key as string).toMatch(/^sk-/)
    apiKeyId = body.id as string
  })

  it('GET /api/api-keys → 200 contains created (raw_key null on read)', async () => {
    const res = await fetch(`${config.baseUrl}/api/api-keys?page_size=100`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    const found = body.data.find((k) => k.id === apiKeyId)
    expect(found).toBeDefined()
    // raw_key is only present in the create response, not on subsequent list/get.
    expect(found?.raw_key).toBeNull()
  })

  it('GET /api/api-keys/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/api-keys/${apiKeyId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(apiKeyId)
    expect(body.raw_key).toBeNull()
  })

  it('GET /api/api-keys?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/api-keys?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { meta: AnyJson; data: AnyJson[] }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/api-keys → 422 on missing name', async () => {
    const res = await fetch(`${config.baseUrl}/api/api-keys`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({ tenant_id: primaryTenantId, role_id: roleId }),
    })
    expect(res.status).toBe(422)
    const body = (await res.json()) as { errors: Array<{ source: { pointer: string } }> }
    expect(body.errors.some((e) => e.source.pointer === '/name')).toBe(true)
  })

  it('POST /api/api-keys → 422 on missing role_id', async () => {
    const res = await fetch(`${config.baseUrl}/api/api-keys`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({ name: 'no-role', tenant_id: primaryTenantId }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/api-keys/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/api-keys/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/api-keys → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/api-keys`, { headers: { accept: 'application/json' } })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary api_key → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/api-keys/${apiKeyId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/api-keys/:id → 204 + GET 404', async () => {
    const del = await fetch(`${config.baseUrl}/api/api-keys/${apiKeyId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/api-keys/${apiKeyId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(get.status).toBe(404)
    apiKeyId = ''
  })
})
