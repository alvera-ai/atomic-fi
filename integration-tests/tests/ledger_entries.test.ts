/**
 * ledger_entries — full CRUD + RLS for /api/ledger-entries.
 *
 * Each entry is a credit/debit posting against a ledger_account. amounts
 * are minor units (integers).
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

describe('ledger_entries — /api/ledger-entries', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let accountHolderId: string
  let ledgerAccountId: string
  let entryId: string

  beforeAll(async () => {
    const session = await postAdminSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-ledger-entries',
    })

    const le = await postJson('/api/legal-entities', bearerHeaders(bearer), {
      legal_entity_type: 'individual',
      first_name: 'LEParent',
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
    const acct = await postJson('/api/ledger-accounts', bearerHeaders(bearer), {
      account_holder_id: accountHolderId,
      ledger_id: ledger.id,
      currency: 'USD',
      account_type: 'asset',
      status: 'active',
      tenant_id: primaryTenantId,
    })
    ledgerAccountId = acct.id as string
  })

  afterAll(async () => {
    if (entryId) await safeDelete(`/api/ledger-entries/${entryId}`, bearerHeaders(bearer))
  })

  it('POST /api/ledger-entries → 201', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-entries`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_holder_id: accountHolderId,
        ledger_account_id: ledgerAccountId,
        currency: 'USD',
        amount: 1000,
        entry_type: 'credit',
        status: 'pending',
        entry_date: '2026-05-01',
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.amount).toBe(1000)
    expect(body.entry_type).toBe('credit')
    entryId = body.id as string
  })

  it('GET /api/ledger-entries → 200 contains created', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-entries?page_size=100&order_by=inserted_at&order_directions=desc`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[] }
    expect(body.data.some((e) => e.id === entryId)).toBe(true)
  })

  it('GET /api/ledger-entries/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-entries/${entryId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(entryId)
  })

  it('PUT /api/ledger-entries/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-entries/${entryId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_holder_id: accountHolderId,
        ledger_account_id: ledgerAccountId,
        currency: 'USD',
        amount: 1000,
        entry_type: 'credit',
        status: 'posted',
        entry_date: '2026-05-01',
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.status).toBe('posted')
  })

  it('GET /api/ledger-entries?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-entries?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/ledger-entries → 422 on missing amount', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-entries`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_holder_id: accountHolderId,
        ledger_account_id: ledgerAccountId,
        currency: 'USD',
        entry_type: 'credit',
        status: 'pending',
        entry_date: '2026-05-01',
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/ledger-entries/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-entries/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/ledger-entries → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-entries`, { headers: { accept: 'application/json' } })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary entry → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-entries/${entryId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/ledger-entries/:id → 204 + GET 404', async () => {
    const del = await fetch(`${config.baseUrl}/api/ledger-entries/${entryId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/ledger-entries/${entryId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(get.status).toBe(404)
    entryId = ''
  })
})
