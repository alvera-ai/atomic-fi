/**
 * payment_accounts — full CRUD + RLS for /api/payment-accounts.
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

describe('payment_accounts — /api/payment-accounts', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let accountHolderId: string
  let paymentAccountId: string

  beforeAll(async () => {
    const session = await postAdminSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-payment-accounts',
    })

    const le = await postJson('/api/legal-entities', bearerHeaders(bearer), {
      legal_entity_type: 'individual',
      first_name: 'PAParent',
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
    if (paymentAccountId) await safeDelete(`/api/payment-accounts/${paymentAccountId}`, bearerHeaders(bearer))
    if (accountHolderId) await safeDelete(`/api/account-holders/${accountHolderId}`, bearerHeaders(bearer))
  })

  it('POST /api/payment-accounts → 201', async () => {
    const res = await fetch(`${config.baseUrl}/api/payment-accounts`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_type: 'bank_account',
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.account_type).toBe('bank_account')
    paymentAccountId = body.id as string
  })

  it('GET /api/payment-accounts → 200 contains created', async () => {
    const res = await fetch(`${config.baseUrl}/api/payment-accounts?page_size=100`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[] }
    expect(body.data.some((p) => p.id === paymentAccountId)).toBe(true)
  })

  it('GET /api/payment-accounts/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/payment-accounts/${paymentAccountId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(paymentAccountId)
  })

  it('PUT /api/payment-accounts/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/payment-accounts/${paymentAccountId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_type: 'bank_account',
        status: 'suspended',
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.status).toBe('suspended')
  })

  it('GET /api/payment-accounts?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/payment-accounts?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/payment-accounts → 422 on missing account_type', async () => {
    const res = await fetch(`${config.baseUrl}/api/payment-accounts`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({ account_holder_id: accountHolderId, tenant_id: primaryTenantId }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/payment-accounts/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/payment-accounts/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/payment-accounts → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/payment-accounts`, { headers: { accept: 'application/json' } })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary payment account → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/payment-accounts/${paymentAccountId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/payment-accounts/:id → 204 + GET 404', async () => {
    const del = await fetch(`${config.baseUrl}/api/payment-accounts/${paymentAccountId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/payment-accounts/${paymentAccountId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(get.status).toBe(404)
    paymentAccountId = ''
  })
})
