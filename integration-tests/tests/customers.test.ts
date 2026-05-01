/**
 * customers — full CRUD + RLS coverage for /api/customers.
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

describe('customers — /api/customers', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let customerId: string
  const suffix = String(Date.now())
  const uniqueSlug = `e2e-customers-${suffix}`
  const uniqueName = `e2e Customers ${suffix}`

  beforeAll(async () => {
    const session = await postSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-customers',
    })
  })

  afterAll(async () => {
    if (customerId) {
      await fetch(`${config.baseUrl}/api/customers/${customerId}`, {
        method: 'DELETE',
        headers: bearerHeaders(bearer),
      }).catch(() => {})
    }
  })

  it('POST /api/customers → 201', async () => {
    const res = await fetch(`${config.baseUrl}/api/customers`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        name: uniqueName,
        slug: uniqueSlug,
        description: 'spec-created customer',
        status: 'active',
        metadata: { tier: 'enterprise' },
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.name).toBe(uniqueName)
    expect(body.slug).toBe(uniqueSlug)
    expect(body.tenant_id).toBe(primaryTenantId)
    customerId = body.id as string
  })

  it('GET /api/customers → 200 contains created', async () => {
    const res = await fetch(`${config.baseUrl}/api/customers?page_size=100`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.some((c) => c.id === customerId)).toBe(true)
  })

  it('GET /api/customers/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/customers/${customerId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(customerId)
  })

  it('PUT /api/customers/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/customers/${customerId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        name: `${uniqueName} (updated)`,
        slug: uniqueSlug,
        description: 'updated',
        status: 'suspended',
        metadata: {},
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(customerId)
    expect(body.status).toBe('suspended')
  })

  it('GET /api/customers?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/customers?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { meta: AnyJson; data: AnyJson[] }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/customers → 422 on missing name', async () => {
    const res = await fetch(`${config.baseUrl}/api/customers`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({ tenant_id: primaryTenantId }),
    })
    expect(res.status).toBe(422)
    const body = (await res.json()) as { errors: Array<{ source: { pointer: string } }> }
    expect(body.errors.some((e) => e.source.pointer === '/name')).toBe(true)
  })

  it('GET /api/customers/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/customers/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/customers → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/customers`, { headers: { accept: 'application/json' } })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary customer → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/customers/${customerId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/customers/:id → 204 + GET 404', async () => {
    const del = await fetch(`${config.baseUrl}/api/customers/${customerId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/customers/${customerId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(get.status).toBe(404)
    customerId = ''
  })
})
