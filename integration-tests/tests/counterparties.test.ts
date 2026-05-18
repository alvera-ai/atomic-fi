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
      account_holder_type: 'individual',
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

  it('POST /api/counterparties with nested legal_entity (cast_assoc) → 201', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        status: 'active',
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
        chain_screening: false,
        legal_entity: {
          legal_entity_type: 'individual',
          first_name: 'NestedCP',
          last_name: 'External',
          date_of_birth: '1985-03-15',
          citizenship_country: 'GB',
          politically_exposed_person: false,
          tenant_id: primaryTenantId,
        },
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.legal_entity_id).toMatch(UUID_RE)
    expect((body.legal_entity as AnyJson).first_name).toBe('NestedCP')
    await safeDelete(`/api/counterparties/${body.id}`, bearerHeaders(bearer))
  })

  it('POST /api/counterparties is get-or-create on external_id → 201 returns same id', async () => {
    // Use a fresh LE so the (account_holder_id, legal_entity_id) pair is
    // distinct from the one already taken by the earlier POST → 201 test
    // (the unique constraint on that pair is orthogonal to get-or-create).
    const freshLe = await postJson('/api/legal-entities', bearerHeaders(bearer), {
      legal_entity_type: 'individual',
      first_name: 'GOC',
      last_name: 'Idempotent',
      date_of_birth: '1990-02-02',
      citizenship_country: 'US',
      politically_exposed_person: false,
      tenant_id: primaryTenantId,
    })
    const freshLeId = freshLe.id as string

    const number = `EXT-IDEMPOTENT-${Date.now()}`
    const post = (extra: Record<string, unknown>) =>
      fetch(`${config.baseUrl}/api/counterparties`, {
        method: 'POST',
        headers: bearerHeaders(bearer),
        body: JSON.stringify({
          status: 'active',
          account_holder_id: accountHolderId,
          legal_entity_id: freshLeId,
          tenant_id: primaryTenantId,
          external_id: number,
          chain_screening: false,
          ...extra,
        }),
      })

    const res1 = await post({})
    expect(res1.status, await res1.clone().text()).toBe(201)
    const body1 = (await res1.json()) as AnyJson

    // Re-POST with same external_id but different status — returns
    // the original record unchanged (external SoE id wins; PUT for updates).
    const res2 = await post({ status: 'suspended' })
    expect(res2.status).toBe(201)
    const body2 = (await res2.json()) as AnyJson

    expect(body2.id).toBe(body1.id)
    expect(body2.status).toBe('active')
    expect(body2.external_id).toBe(number)

    await safeDelete(`/api/counterparties/${body1.id as string}`, bearerHeaders(bearer))
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

  it('POST /api/counterparties → 422 when neither legal_entity_id nor nested legal_entity supplied', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        status: 'active',
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
        chain_screening: false,
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
