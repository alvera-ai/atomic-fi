/**
 * compliance_screenings — index + show + 3 screening action endpoints.
 *
 * The `/api/compliance-screenings/screen-{account-holder,beneficial-owner,
 * counterparty}` endpoints invoke the real Watchman dev container. We
 * provision a legal_entity + account_holder + beneficial_owner + counterparty
 * in beforeAll, then exercise each screening action.
 *
 * Watchman returns one of: pass | potential_match | blocked. We accept all
 * three so the spec stays green regardless of the custom screening list's
 * current contents.
 */
import { beforeAll, describe, expect, it } from 'vitest'

import { mintSecondaryTenant, type SecondaryTenant } from '@atomic-fi/sdk'

import { config } from '../src/env.ts'
import {
  apiKeyHeaders,
  bearerHeaders,
  postAdminSession,
  UUID_RE,
  type AnyJson,
} from '../src/test-helpers.ts'

async function postJson(path: string, headers: Record<string, string>, body: unknown): Promise<AnyJson> {
  const res = await fetch(`${config.baseUrl}${path}`, { method: 'POST', headers, body: JSON.stringify(body) })
  if (!res.ok) throw new Error(`${path} → ${res.status}: ${await res.text()}`)
  return (await res.json()) as AnyJson
}

const VALID_STATUSES = ['pass', 'potential_match', 'blocked']

describe('compliance_screenings — /api/compliance-screenings', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let accountHolderId: string
  let legalEntityId: string
  let beneficialOwnerId: string
  let counterpartyId: string
  let firstScreeningId: string

  beforeAll(async () => {
    const session = await postAdminSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-screenings',
    })

    const le = await postJson('/api/legal-entities', bearerHeaders(bearer), {
      legal_entity_type: 'individual',
      first_name: 'Alice',
      last_name: 'Smith',
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

    const bo = await postJson('/api/beneficial-owners', bearerHeaders(bearer), {
      control_type: 'shareholder',
      ownership_pct: 25.0,
      verification_status: 'pending',
      legal_entity_id: legalEntityId,
      account_holder_id: accountHolderId,
      tenant_id: primaryTenantId,
    })
    beneficialOwnerId = bo.id as string

    const cp = await postJson('/api/counterparties', bearerHeaders(bearer), {
      status: 'active',
      legal_entity_id: legalEntityId,
      account_holder_id: accountHolderId,
      tenant_id: primaryTenantId,
    })
    counterpartyId = cp.id as string

    // Initialize the per-tenant blocklist cache; screening endpoints require
    // it (otherwise they raise "BlocklistCache not initialized" — by design,
    // to prevent allowing blocked entities through due to an empty cache).
    const refresh = await fetch(`${config.baseUrl}/api/tenants/refresh-blocklist-cache`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
    })
    if (!refresh.ok) {
      throw new Error(`refresh-blocklist-cache → ${refresh.status}: ${await refresh.text()}`)
    }
  })

  it('POST /api/compliance-screenings/screen-account-holder → 200 with screening row', async (ctx) => {
    const res = await fetch(`${config.baseUrl}/api/compliance-screenings/screen-account-holder`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({ account_holder_id: accountHolderId }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson[]
    expect(Array.isArray(body)).toBe(true)
    expect(body.length).toBeGreaterThanOrEqual(1)
    const [first] = body
    expect(first.id).toMatch(UUID_RE)
    expect(first.scope).toBe('account_holder')
    expect(first.screening_type).toBe('sanctions')
    expect(VALID_STATUSES).toContain(first.screening_status)
    firstScreeningId = first.id as string
  })

  it('POST /api/compliance-screenings/screen-beneficial-owner → 200', async (ctx) => {
    const res = await fetch(`${config.baseUrl}/api/compliance-screenings/screen-beneficial-owner`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_holder_id: accountHolderId,
        beneficial_owner_id: beneficialOwnerId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson[]
    expect(body.length).toBeGreaterThanOrEqual(1)
    expect(body[0].scope).toBe('beneficial_owner')
    expect(VALID_STATUSES).toContain(body[0].screening_status)
  })

  it('POST /api/compliance-screenings/screen-counterparty → 200', async (ctx) => {
    const res = await fetch(`${config.baseUrl}/api/compliance-screenings/screen-counterparty`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_holder_id: accountHolderId,
        counterparty_id: counterpartyId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson[]
    expect(body.length).toBeGreaterThanOrEqual(1)
    expect(body[0].scope).toBe('counterparty')
    expect(VALID_STATUSES).toContain(body[0].screening_status)
  })

  it('GET /api/compliance-screenings → 200 contains the prior screening', async (ctx) => {
    const res = await fetch(`${config.baseUrl}/api/compliance-screenings?page_size=100`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[] }
    expect(body.data.some((s) => s.id === firstScreeningId)).toBe(true)
  })

  it('GET /api/compliance-screenings/:id → 200', async (ctx) => {
    const res = await fetch(`${config.baseUrl}/api/compliance-screenings/${firstScreeningId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(firstScreeningId)
  })

  it('GET /api/compliance-screenings?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/compliance-screenings?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('GET /api/compliance-screenings/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/compliance-screenings/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/compliance-screenings → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/compliance-screenings`, {
      headers: { accept: 'application/json' },
    })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary screening → 404', async (ctx) => {
    const res = await fetch(`${config.baseUrl}/api/compliance-screenings/${firstScreeningId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })
})
