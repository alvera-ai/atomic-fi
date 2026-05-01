/**
 * users — full CRUD + RLS coverage for /api/users.
 *
 * Self-contained: signs in as the seeded admin in beforeAll, captures the
 * primary bearer, mints a secondary tenant + api key for the RLS case.
 * Cases run sequentially and reuse `userId` captured from the create case.
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest'

import { mintSecondaryTenant, type SecondaryTenant } from '@atomic-fi/sdk'

import { config } from '../src/env.ts'

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/

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

function bearerHeaders(bearer: string): Record<string, string> {
  return {
    authorization: `Bearer ${bearer}`,
    'content-type': 'application/json',
    accept: 'application/json',
  }
}

function apiKeyHeaders(apiKey: string): Record<string, string> {
  return { 'x-api-key': apiKey, 'content-type': 'application/json', accept: 'application/json' }
}

describe('users — /api/users', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let userId: string
  const uniqueEmail = `e2e-users-${Date.now()}@example.test`

  beforeAll(async () => {
    const session = await postSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId

    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-users',
    })
  })

  afterAll(async () => {
    if (userId) {
      await fetch(`${config.baseUrl}/api/users/${userId}`, {
        method: 'DELETE',
        headers: bearerHeaders(bearer),
      }).catch(() => {})
    }
  })

  it('POST /api/users → 201 creates a user', async () => {
    const res = await fetch(`${config.baseUrl}/api/users`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        email: uniqueEmail,
        hashed_password: '$2b$12$abcdefghijklmnopqrstuv',
        confirmed_at: new Date().toISOString(),
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.email).toBe(uniqueEmail)
    expect(body.tenant_id).toBe(primaryTenantId)
    expect(body.inserted_at as string).toMatch(ISO_RE)
    userId = body.id as string
  })

  it('GET /api/users → 200 list contains the new user', async () => {
    const res = await fetch(`${config.baseUrl}/api/users`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(Array.isArray(body.data)).toBe(true)
    expect(body.meta.total_count as number).toBeGreaterThanOrEqual(1)
    expect(body.data.some((u) => u.id === userId)).toBe(true)
  })

  it('GET /api/users/:id → 200 fetches by id', async () => {
    const res = await fetch(`${config.baseUrl}/api/users/${userId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(userId)
    expect(body.email).toBe(uniqueEmail)
  })

  it('PUT /api/users/:id → 200 updates email', async () => {
    const updatedEmail = `updated-${Date.now()}@example.test`
    const res = await fetch(`${config.baseUrl}/api/users/${userId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        email: updatedEmail,
        hashed_password: '$2b$12$abcdefghijklmnopqrstuv',
        confirmed_at: new Date().toISOString(),
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(userId)
    expect(body.email).toBe(updatedEmail)
  })

  it('GET /api/users?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/users?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
    expect(body.meta.page).toBe(1)
  })

  it('POST /api/users → 422 on missing email', async () => {
    const res = await fetch(`${config.baseUrl}/api/users`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        hashed_password: '$2b$12$abc',
        confirmed_at: new Date().toISOString(),
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status).toBe(422)
    const body = (await res.json()) as { errors: Array<{ source: { pointer: string } }> }
    expect(body.errors.some((e) => e.source.pointer === '/email')).toBe(true)
  })

  it('GET /api/users/:id → 404 for unknown id', async () => {
    const fake = '00000000-0000-0000-0000-000000000000'
    const res = await fetch(`${config.baseUrl}/api/users/${fake}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/users → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/users`, {
      headers: { accept: 'application/json' },
    })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary user → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/users/${userId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/users/:id → 204 + subsequent GET 404', async () => {
    const del = await fetch(`${config.baseUrl}/api/users/${userId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/users/${userId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(get.status).toBe(404)
    userId = '' // signal afterAll: nothing to clean
  })
})
