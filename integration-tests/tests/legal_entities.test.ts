/**
 * legal_entities — full CRUD + RLS for /api/legal-entities.
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest'

import { mintSecondaryTenant, type SecondaryTenant } from '@atomic-fi/sdk'

import { config } from '../src/env.ts'
import {
  apiKeyHeaders,
  bearerHeaders,
  postAdminSession,
  safeDelete,
  UUID_RE,
  type AnyJson,
} from '../src/test-helpers.ts'

describe('legal_entities — /api/legal-entities', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let entityId: string

  beforeAll(async () => {
    const session = await postAdminSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-legal-entities',
    })
  })

  afterAll(async () => {
    if (entityId) await safeDelete(`/api/legal-entities/${entityId}`, bearerHeaders(bearer))
  })

  it('POST /api/legal-entities → 201 (individual)', async () => {
    const res = await fetch(`${config.baseUrl}/api/legal-entities`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        legal_entity_type: 'individual',
        first_name: 'John',
        last_name: 'Doe',
        date_of_birth: '1990-01-01',
        citizenship_country: 'US',
        politically_exposed_person: false,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.legal_entity_type).toBe('individual')
    expect(body.first_name).toBe('John')
    entityId = body.id as string
  })

  it('GET /api/legal-entities → 200 contains created', async () => {
    const res = await fetch(`${config.baseUrl}/api/legal-entities?page_size=100`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[] }
    expect(body.data.some((e) => e.id === entityId)).toBe(true)
  })

  it('GET /api/legal-entities/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/legal-entities/${entityId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(entityId)
  })

  it('PUT /api/legal-entities/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/legal-entities/${entityId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        legal_entity_type: 'individual',
        first_name: 'Johnny',
        last_name: 'Doe',
        date_of_birth: '1990-01-01',
        citizenship_country: 'US',
        politically_exposed_person: true,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.first_name).toBe('Johnny')
    expect(body.politically_exposed_person).toBe(true)
  })

  it('GET /api/legal-entities?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/legal-entities?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/legal-entities → 422 on missing legal_entity_type', async () => {
    const res = await fetch(`${config.baseUrl}/api/legal-entities`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({ first_name: 'X', last_name: 'Y', tenant_id: primaryTenantId }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/legal-entities/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/legal-entities/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/legal-entities → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/legal-entities`, { headers: { accept: 'application/json' } })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary entity → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/legal-entities/${entityId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/legal-entities/:id → 204 + GET 404', async () => {
    const del = await fetch(`${config.baseUrl}/api/legal-entities/${entityId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/legal-entities/${entityId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(get.status).toBe(404)
    entityId = ''
  })
})
