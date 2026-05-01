/**
 * tenants — full CRUD coverage for /api/tenants.
 *
 * Tenant CRUD requires the platform_admin api key (admin bearer with role=root
 * doesn't carry the platform_admin_api permission). We auth with x-api-key
 * end-to-end here.
 *
 * RLS is implicit: every tenant is its own root, and listing returns only
 * platform-visible tenants. We assert that an api key scoped to a freshly-
 * minted SECONDARY tenant cannot read a tenant created by the primary
 * platform_admin (404).
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest'

import { mintSecondaryTenant, type SecondaryTenant } from '@atomic-fi/sdk'

import { config } from '../src/env.ts'

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

type AnyJson = Record<string, unknown>

const json = (extra: Record<string, string> = {}) => ({
  'content-type': 'application/json',
  accept: 'application/json',
  ...extra,
})
const adminHeaders = json({ 'x-api-key': config.platformAdminApiKey })
const apiKeyHeaders = (k: string) => json({ 'x-api-key': k })

describe('tenants — /api/tenants', () => {
  let secondary: SecondaryTenant
  let tenantId: string
  const suffix = String(Date.now())
  const uniqueName = `e2e-tenants-${suffix}`
  const uniqueSlug = `e2e-tenants-${suffix}`

  beforeAll(async () => {
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-tenants',
    })
  })

  afterAll(async () => {
    if (tenantId) {
      await fetch(`${config.baseUrl}/api/tenants/${tenantId}`, {
        method: 'DELETE',
        headers: adminHeaders,
      }).catch(() => {})
    }
  })

  it('POST /api/tenants → 201', async () => {
    const res = await fetch(`${config.baseUrl}/api/tenants`, {
      method: 'POST',
      headers: adminHeaders,
      body: JSON.stringify({
        name: uniqueName,
        slug: uniqueSlug,
        tenant_type: 'standard',
        status: 'active',
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.name).toBe(uniqueName)
    expect(body.tenant_type).toBe('standard')
    expect(body.status).toBe('active')
    tenantId = body.id as string
  })

  it('GET /api/tenants → 200 contains created', async () => {
    const res = await fetch(`${config.baseUrl}/api/tenants?page_size=100`, {
      headers: adminHeaders,
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.some((t) => t.id === tenantId)).toBe(true)
  })

  it('GET /api/tenants/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/tenants/${tenantId}`, { headers: adminHeaders })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(tenantId)
    expect(body.slug).toBe(uniqueSlug)
  })

  it('PUT /api/tenants/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/tenants/${tenantId}`, {
      method: 'PUT',
      headers: adminHeaders,
      body: JSON.stringify({
        name: `${uniqueName}-updated`,
        slug: uniqueSlug,
        tenant_type: 'standard',
        status: 'suspended',
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.name).toBe(`${uniqueName}-updated`)
    expect(body.status).toBe('suspended')
  })

  it('GET /api/tenants?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/tenants?page=1&page_size=5`, {
      headers: adminHeaders,
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { meta: AnyJson; data: AnyJson[] }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/tenants → 422 on missing name', async () => {
    const res = await fetch(`${config.baseUrl}/api/tenants`, {
      method: 'POST',
      headers: adminHeaders,
      body: JSON.stringify({ tenant_type: 'standard', status: 'active' }),
    })
    expect(res.status).toBe(422)
    const body = (await res.json()) as { errors: Array<{ source: { pointer: string } }> }
    expect(body.errors.some((e) => e.source.pointer === '/name')).toBe(true)
  })

  it('POST /api/tenants → 422 on invalid tenant_type', async () => {
    const res = await fetch(`${config.baseUrl}/api/tenants`, {
      method: 'POST',
      headers: adminHeaders,
      body: JSON.stringify({
        name: 'invalid-type',
        slug: 'invalid-type',
        tenant_type: 'not_a_type',
        status: 'active',
      }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/tenants/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/tenants/00000000-0000-0000-0000-000000000000`, {
      headers: adminHeaders,
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/tenants → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/tenants`, { headers: { accept: 'application/json' } })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary (non-platform) tenant cannot see other tenants → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/tenants/${tenantId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    // A standard-tenant api key is not platform_admin and should not see another tenant.
    // Spec accepts either 404 (RLS-scoped, returns nothing) or 403 (auth-rejected),
    // both indicate isolation. Phoenix returns 404 in current impl.
    expect([403, 404]).toContain(res.status)
  })

  it('DELETE /api/tenants/:id → 204 + GET 404', async () => {
    const del = await fetch(`${config.baseUrl}/api/tenants/${tenantId}`, {
      method: 'DELETE',
      headers: adminHeaders,
    })
    expect(del.status).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/tenants/${tenantId}`, { headers: adminHeaders })
    expect(get.status).toBe(404)
    tenantId = ''
  })
})
