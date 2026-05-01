/**
 * transactions — full CRUD + RLS for /api/transactions.
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

describe('transactions — /api/transactions', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let accountHolderId: string
  let txId: string

  beforeAll(async () => {
    const session = await postAdminSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-transactions',
    })

    const le = await postJson('/api/legal-entities', bearerHeaders(bearer), {
      legal_entity_type: 'individual',
      first_name: 'TxParent',
      last_name: 'X',
      date_of_birth: '1990-01-01',
      citizenship_country: 'US',
      politically_exposed_person: false,
      tenant_id: primaryTenantId,
    })
    const ah = await postJson('/api/account-holders', bearerHeaders(bearer), {
      holder_type: 'individual',
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
    if (txId) await safeDelete(`/api/transactions/${txId}`, bearerHeaders(bearer))
  })

  it('POST /api/transactions → 201', async () => {
    const res = await fetch(`${config.baseUrl}/api/transactions`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        transaction_type: 'credit_transfer',
        amount: 10000,
        currency: 'USD',
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.amount).toBe(10000)
    expect(body.transaction_type).toBe('credit_transfer')
    txId = body.id as string
  })

  it('GET /api/transactions → 200 contains created', async () => {
    const res = await fetch(`${config.baseUrl}/api/transactions?page_size=100&order_by=inserted_at&order_directions=desc`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[] }
    expect(body.data.some((t) => t.id === txId)).toBe(true)
  })

  it('GET /api/transactions/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/transactions/${txId}`, { headers: bearerHeaders(bearer) })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(txId)
  })

  it('PUT /api/transactions/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/transactions/${txId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        transaction_type: 'credit_transfer',
        status: 'settled',
        amount: 10000,
        currency: 'USD',
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.status).toBe('settled')
  })

  it('GET /api/transactions?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/transactions?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/transactions → 422 on missing amount', async () => {
    const res = await fetch(`${config.baseUrl}/api/transactions`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        transaction_type: 'credit_transfer',
        currency: 'USD',
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status).toBe(422)
  })

  it('POST /api/transactions → 422 on amount <= 0', async () => {
    const res = await fetch(`${config.baseUrl}/api/transactions`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        transaction_type: 'credit_transfer',
        amount: 0,
        currency: 'USD',
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/transactions/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/transactions/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/transactions → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/transactions`, { headers: { accept: 'application/json' } })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary tx → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/transactions/${txId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/transactions/:id → 204 + GET 404', async () => {
    const del = await fetch(`${config.baseUrl}/api/transactions/${txId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/transactions/${txId}`, { headers: bearerHeaders(bearer) })
    expect(get.status).toBe(404)
    txId = ''
  })
})
