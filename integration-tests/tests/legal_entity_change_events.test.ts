/**
 * legal_entity_change_events — full CRUD + RLS for /api/legal-entity-change-events.
 *
 * Each event needs a parent legal_entity. We provision one in beforeAll.
 * Cleanup is best-effort; deletion of a legal_entity that has been touched
 * by change events is currently blocked by #17, so the parent entity
 * intentionally leaks across runs (per-runId scoping keeps it harmless).
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

describe('legal_entity_change_events — /api/legal-entity-change-events', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let legalEntityId: string
  let eventId: string

  beforeAll(async () => {
    const session = await postAdminSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-le-events',
    })

    const leRes = await fetch(`${config.baseUrl}/api/legal-entities`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        legal_entity_type: 'individual',
        first_name: 'EventParent',
        last_name: 'X',
        date_of_birth: '1990-01-01',
        citizenship_country: 'US',
        politically_exposed_person: false,
        tenant_id: primaryTenantId,
      }),
    })
    if (!leRes.ok) {
      throw new Error(`legal_entity beforeAll: ${leRes.status} ${await leRes.text()}`)
    }
    legalEntityId = ((await leRes.json()) as { id: string }).id
  })

  afterAll(async () => {
    if (eventId) await safeDelete(`/api/legal-entity-change-events/${eventId}`, bearerHeaders(bearer))
    // Don't try to delete the parent legal_entity — blocked by #17.
  })

  it('POST /api/legal-entity-change-events → 201', async () => {
    const res = await fetch(`${config.baseUrl}/api/legal-entity-change-events`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        event_type: 'address_change',
        change_channel: 'web',
        legal_entity_id: legalEntityId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.event_type).toBe('address_change')
    expect(body.change_channel).toBe('web')
    eventId = body.id as string
  })

  it('GET /api/legal-entity-change-events → 200 contains created', async () => {
    const res = await fetch(`${config.baseUrl}/api/legal-entity-change-events?page_size=100&order_by=inserted_at&order_directions=desc`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[] }
    expect(body.data.some((e) => e.id === eventId)).toBe(true)
  })

  it('GET /api/legal-entity-change-events/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/legal-entity-change-events/${eventId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(eventId)
  })

  it('PUT /api/legal-entity-change-events/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/legal-entity-change-events/${eventId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        event_type: 'address_change',
        change_channel: 'branch',
        event_status: 'confirmed',
        legal_entity_id: legalEntityId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.change_channel).toBe('branch')
    expect(body.event_status).toBe('confirmed')
  })

  it('GET /api/legal-entity-change-events?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/legal-entity-change-events?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/legal-entity-change-events → 422 on missing event_type', async () => {
    const res = await fetch(`${config.baseUrl}/api/legal-entity-change-events`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        change_channel: 'web',
        legal_entity_id: legalEntityId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/legal-entity-change-events/:id → 404 for unknown id', async () => {
    const res = await fetch(
      `${config.baseUrl}/api/legal-entity-change-events/00000000-0000-0000-0000-000000000000`,
      { headers: bearerHeaders(bearer) },
    )
    expect(res.status).toBe(404)
  })

  it('GET /api/legal-entity-change-events → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/legal-entity-change-events`, {
      headers: { accept: 'application/json' },
    })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary event → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/legal-entity-change-events/${eventId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/legal-entity-change-events/:id → 204 + GET 404', async () => {
    const del = await fetch(`${config.baseUrl}/api/legal-entity-change-events/${eventId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/legal-entity-change-events/${eventId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(get.status).toBe(404)
    eventId = ''
  })
})
