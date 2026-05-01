/**
 * counterparties — full CRUD + RLS for /api/counterparties.
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

async function postJson(path: string, headers: Record<string, string>, body: unknown): Promise<AnyJson> {
  const res = await fetch(`${config.baseUrl}${path}`, { method: 'POST', headers, body: JSON.stringify(body) })
  if (!res.ok) throw new Error(`${path} → ${res.status}: ${await res.text()}`)
  return (await res.json()) as AnyJson
}

describe('counterparties — /api/counterparties', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let legalEntityId: string
  let accountHolderId: string
  let counterpartyId: string

  beforeAll(async () => {
    const session = await postAdminSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-counterparties',
    })

    const le = await postJson('/api/legal-entities', bearerHeaders(bearer), {
      legal_entity_type: 'individual',
      first_name: 'CPParent',
      last_name: 'X',
      date_of_birth: '1990-01-01',
      citizenship_country: 'US',
      politically_exposed_person: false,
      tenant_id: primaryTenantId,
    })
    legalEntityId = le.id as string
    const ah = await postJson('/api/account-holders', bearerHeaders(bearer), {
      holder_type: 'individual',
      status: 'pending',
      kyc_status: 'not_started',
      risk_level: 'low',
      enabled_currencies: ['USD'],
      legal_entity_id: legalEntityId,
      tenant_id: primaryTenantId,
    })
    accountHolderId = ah.id as string
  })

  afterAll(async () => {
    if (counterpartyId) await safeDelete(`/api/counterparties/${counterpartyId}`, bearerHeaders(bearer))
  })

  it('POST /api/counterparties → 201', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        status: 'active',
        legal_entity_id: legalEntityId,
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.status).toBe('active')
    counterpartyId = body.id as string
  })

  it('GET /api/counterparties → 200 contains created', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties?page_size=100&order_by=inserted_at&order_directions=desc`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[] }
    expect(body.data.some((c) => c.id === counterpartyId)).toBe(true)
  })

  it('GET /api/counterparties/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties/${counterpartyId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(counterpartyId)
  })

  it('PUT /api/counterparties/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties/${counterpartyId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        status: 'suspended',
        legal_entity_id: legalEntityId,
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.status).toBe('suspended')
  })

  it('GET /api/counterparties?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/counterparties → 422 on missing status', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        legal_entity_id: legalEntityId,
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/counterparties/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/counterparties → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties`, { headers: { accept: 'application/json' } })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary counterparty → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties/${counterpartyId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/counterparties/:id → 204 + GET 404', async () => {
    const del = await fetch(`${config.baseUrl}/api/counterparties/${counterpartyId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/counterparties/${counterpartyId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(get.status).toBe(404)
    counterpartyId = ''
  })
})
