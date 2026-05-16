/**
 * ledger_accounts — full CRUD + RLS for /api/ledger-accounts.
 *
 * Each ledger_account belongs to a (ledger, account_holder) pair. Unique on
 * (ledger_id, account_type), so the spec uses :asset for create and a fresh
 * :liability for additional create cases (none here, but kept in mind).
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

describe('ledger_accounts — /api/ledger-accounts', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let accountHolderId: string
  let ledgerId: string
  let accountId: string

  beforeAll(async () => {
    const session = await postAdminSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-ledger-accounts',
    })

    const le = await postJson('/api/legal-entities', bearerHeaders(bearer), {
      legal_entity_type: 'individual',
      first_name: 'LAParent',
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
    const ledger = await postJson('/api/ledgers', bearerHeaders(bearer), {
      account_holder_id: accountHolderId,
      currency: 'USD',
      status: 'active',
      tenant_id: primaryTenantId,
    })
    ledgerId = ledger.id as string
  })

  afterAll(async () => {
    if (accountId) await safeDelete(`/api/ledger-accounts/${accountId}`, bearerHeaders(bearer))
    if (ledgerId) await safeDelete(`/api/ledgers/${ledgerId}`, bearerHeaders(bearer))
    if (accountHolderId) await safeDelete(`/api/account-holders/${accountHolderId}`, bearerHeaders(bearer))
  })

  it('POST /api/ledger-accounts → 201', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-accounts`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_holder_id: accountHolderId,
        ledger_id: ledgerId,
        currency: 'USD',
        account_type: 'asset',
        status: 'active',
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.account_type).toBe('asset')
    expect(body.ledger_id).toBe(ledgerId)
    accountId = body.id as string
  })

  it('GET /api/ledger-accounts → 200 contains created', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-accounts?page_size=100&order_by=inserted_at&order_directions=desc`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[] }
    expect(body.data.some((a) => a.id === accountId)).toBe(true)
  })

  it('GET /api/ledger-accounts/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-accounts/${accountId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(accountId)
  })

  it('PUT /api/ledger-accounts/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-accounts/${accountId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_holder_id: accountHolderId,
        ledger_id: ledgerId,
        currency: 'USD',
        account_type: 'asset',
        status: 'closed',
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.status).toBe('closed')
  })

  it('GET /api/ledger-accounts?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-accounts?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/ledger-accounts → 422 on missing currency', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-accounts`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_holder_id: accountHolderId,
        ledger_id: ledgerId,
        account_type: 'asset',
        status: 'active',
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/ledger-accounts/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-accounts/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/ledger-accounts → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-accounts`, { headers: { accept: 'application/json' } })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary account → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-accounts/${accountId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/ledger-accounts/:id → 204 + GET 404', async () => {
    const del = await fetch(`${config.baseUrl}/api/ledger-accounts/${accountId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/ledger-accounts/${accountId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(get.status).toBe(404)
    accountId = ''
  })
})
