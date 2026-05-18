/**
 * risk_classifications — full CRUD + RLS for /api/risk-classifications.
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

const today = new Date().toISOString().slice(0, 10)

describe('risk_classifications — /api/risk-classifications', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let accountHolderId: string
  let classificationId: string

  beforeAll(async () => {
    const session = await postAdminSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-rc',
    })

    const le = await postJson('/api/legal-entities', bearerHeaders(bearer), {
      legal_entity_type: 'individual',
      first_name: 'RCParent',
      last_name: 'X',
      date_of_birth: '1990-01-01',
      citizenship_country: 'US',
      politically_exposed_person: false,
      tenant_id: primaryTenantId,
    })
    const ah = await postJson('/api/account-holders', bearerHeaders(bearer), {
      account_holder_type: 'individual',
      status: 'pending',
      kyc_status: 'not_started',
      risk_level: 'low',
      enabled_currencies: ['USD'],
      legal_entity_id: le.id,
      tenant_id: primaryTenantId,
    })
    accountHolderId = ah.id as string
  })

  afterAll(async () => {
    if (classificationId) await safeDelete(`/api/risk-classifications/${classificationId}`, bearerHeaders(bearer))
  })

  it('POST /api/risk-classifications → 201', async () => {
    const res = await fetch(`${config.baseUrl}/api/risk-classifications`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_holder_id: accountHolderId,
        risk_level: 'high',
        classification_reason: 'Large inbound volume',
        effective_from: today,
        is_active: true,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.risk_level).toBe('high')
    classificationId = body.id as string
  })

  it('GET /api/risk-classifications → 200 contains created', async () => {
    const res = await fetch(
      `${config.baseUrl}/api/risk-classifications?page_size=100&order_by=inserted_at&order_directions=desc`,
      { headers: bearerHeaders(bearer) },
    )
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[] }
    expect(body.data.some((r) => r.id === classificationId)).toBe(true)
  })

  it('GET /api/risk-classifications/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/risk-classifications/${classificationId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(classificationId)
  })

  it('PUT /api/risk-classifications/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/risk-classifications/${classificationId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_holder_id: accountHolderId,
        risk_level: 'very_high',
        classification_reason: 'Adverse media hit',
        effective_from: today,
        is_active: false,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.risk_level).toBe('very_high')
    expect(body.is_active).toBe(false)
  })

  it('GET /api/risk-classifications?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/risk-classifications?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/risk-classifications → 422 on missing required', async () => {
    const res = await fetch(`${config.baseUrl}/api/risk-classifications`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({ tenant_id: primaryTenantId }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/risk-classifications/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/risk-classifications/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/risk-classifications → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/risk-classifications`, {
      headers: { accept: 'application/json' },
    })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary classification → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/risk-classifications/${classificationId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/risk-classifications/:id → 204 + GET 404', async () => {
    const del = await fetch(`${config.baseUrl}/api/risk-classifications/${classificationId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/risk-classifications/${classificationId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(get.status).toBe(404)
    classificationId = ''
  })
})
