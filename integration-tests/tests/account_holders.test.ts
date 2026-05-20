/**
 * account_holders — full CRUD + RLS for /api/account-holders.
 *
 * LegalEntity is created atomically via the nested `legal_entity` object on
 * POST. The LE link is immutable post-create — replacing the AH's PII goes
 * through the dedicated `PUT /api/account-holders/:id/legal-entity` route
 * (covered in legal_entities.test.ts).
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest'

import { mintSecondaryTenant, type SecondaryTenant } from '@atomic-fi/sdk'

import { config } from '../src/env.ts'
import {
  apiKeyHeaders,
  bearerHeaders,
  defaultIndividualLegalEntity,
  postAdminSession,
  safeDelete,
  UUID_RE,
  warmupBlocklistCache,
  type AnyJson,
} from '../src/test-helpers.ts'

describe('account_holders — /api/account-holders', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let holderId: string

  beforeAll(async () => {
    const session = await postAdminSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-account-holders',
    })
    await warmupBlocklistCache(bearer)
  })

  afterAll(async () => {
    if (holderId) await safeDelete(`/api/account-holders/${holderId}`, bearerHeaders(bearer))
  })

  it('POST /api/account-holders → 201', async () => {
    const res = await fetch(`${config.baseUrl}/api/account-holders`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_holder_type: 'individual',
        status: 'pending',
        kyc_status: 'not_started',
        risk_level: 'low',
        enabled_currencies: ['USD'],
        chain_screening: false,
        legal_entity: defaultIndividualLegalEntity(primaryTenantId, 'AH'),
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.account_holder_type).toBe('individual')
    expect(body.kyc_status).toBe('not_started')
    holderId = body.id as string
  })

  it('GET /api/account-holders → 200 contains created', async () => {
    const res = await fetch(`${config.baseUrl}/api/account-holders?page_size=100&order_by=inserted_at&order_directions=desc`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[] }
    expect(body.data.some((h) => h.id === holderId)).toBe(true)
  })

  it('GET /api/account-holders/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/account-holders/${holderId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(holderId)
  })

  it('PUT /api/account-holders/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/account-holders/${holderId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_holder_type: 'business',
        status: 'active',
        kyc_status: 'approved',
        risk_level: 'medium',
        enabled_currencies: ['USD', 'EUR'],
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.status).toBe('active')
    expect(body.kyc_status).toBe('approved')
  })

  it('GET /api/account-holders?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/account-holders?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/account-holders → 422 on missing account_holder_type', async () => {
    const res = await fetch(`${config.baseUrl}/api/account-holders`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        status: 'pending',
        kyc_status: 'not_started',
        chain_screening: false,
        legal_entity: defaultIndividualLegalEntity(primaryTenantId, 'AH-Missing'),
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/account-holders/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/account-holders/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/account-holders → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/account-holders`, { headers: { accept: 'application/json' } })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary holder → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/account-holders/${holderId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/account-holders/:id → 422 when ledger tree exists', async () => {
    // POST through the controller triggers the synchronous onboard pipeline
    // which materialises ledgers / ledger_accounts. Those FKs are
    // ON DELETE RESTRICT, surfaced as a changeset error → 422.
    const del = await fetch(`${config.baseUrl}/api/account-holders/${holderId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status, await del.clone().text()).toBe(422)

    const body = (await del.json()) as { errors: { detail: string }[] }
    expect(body.errors.some((e) => e.detail.includes('exist for this account holder'))).toBe(true)

    // AH is still queryable — DELETE didn't take effect.
    const get = await fetch(`${config.baseUrl}/api/account-holders/${holderId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(get.status).toBe(200)
  })
})
