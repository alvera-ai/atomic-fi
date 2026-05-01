/**
 * roles — full CRUD + RLS coverage for /api/roles.
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

const json = (extra: Record<string, string> = {}) => ({
  'content-type': 'application/json',
  accept: 'application/json',
  ...extra,
})
const bearerHeaders = (b: string) => json({ authorization: `Bearer ${b}` })
const apiKeyHeaders = (k: string) => json({ 'x-api-key': k })

describe('roles — /api/roles', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let roleId: string
  const uniqueName = `e2e_roles_${Date.now()}`

  beforeAll(async () => {
    const session = await postSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId

    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-roles',
    })
  })

  afterAll(async () => {
    if (roleId) {
      await fetch(`${config.baseUrl}/api/roles/${roleId}`, {
        method: 'DELETE',
        headers: bearerHeaders(bearer),
      }).catch(() => {})
    }
  })

  it('POST /api/roles → 201 creates a role', async () => {
    const res = await fetch(`${config.baseUrl}/api/roles`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        name: uniqueName,
        description: 'spec-created role',
        metadata: { source: 'e2e' },
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.name).toBe(uniqueName)
    expect(body.tenant_id).toBe(primaryTenantId)
    expect(body.metadata).toEqual({ source: 'e2e' })
    expect(body.inserted_at as string).toMatch(ISO_RE)
    roleId = body.id as string
  })

  it('GET /api/roles → 200 list contains created', async () => {
    // Order by inserted_at desc so the freshly-created role lands on page 1
    // regardless of how many seed/historical roles already exist.
    const res = await fetch(
      `${config.baseUrl}/api/roles?page_size=100&order_by=inserted_at&order_directions=desc`,
      { headers: bearerHeaders(bearer) },
    )
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.meta.total_count as number).toBeGreaterThanOrEqual(1)
    expect(body.data.some((r) => r.id === roleId)).toBe(true)
  })

  it('GET /api/roles/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/roles/${roleId}`, { headers: bearerHeaders(bearer) })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(roleId)
    expect(body.name).toBe(uniqueName)
  })

  it('PUT /api/roles/:id → 200 updates description + metadata', async () => {
    const res = await fetch(`${config.baseUrl}/api/roles/${roleId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        name: uniqueName,
        description: 'updated description',
        metadata: { updated: true },
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(roleId)
    expect(body.description).toBe('updated description')
    expect(body.metadata).toEqual({ updated: true })
  })

  it('GET /api/roles?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/roles?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
    expect(body.meta.page).toBe(1)
  })

  it('POST /api/roles → 422 on missing name', async () => {
    const res = await fetch(`${config.baseUrl}/api/roles`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        description: 'no name',
        metadata: {},
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status).toBe(422)
    const body = (await res.json()) as { errors: Array<{ source: { pointer: string } }> }
    expect(body.errors.some((e) => e.source.pointer === '/name')).toBe(true)
  })

  it('POST /api/roles → 422 on reserved name "root"', async () => {
    const res = await fetch(`${config.baseUrl}/api/roles`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        name: 'root',
        description: 'reserved',
        metadata: {},
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/roles/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/roles/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/roles → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/roles`, { headers: { accept: 'application/json' } })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary role → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/roles/${roleId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/roles/:id → 204 + GET 404', async () => {
    const del = await fetch(`${config.baseUrl}/api/roles/${roleId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/roles/${roleId}`, { headers: bearerHeaders(bearer) })
    expect(get.status).toBe(404)
    roleId = ''
  })
})
