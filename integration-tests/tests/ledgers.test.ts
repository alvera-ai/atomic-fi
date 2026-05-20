/**
 * ledgers — full CRUD + RLS for /api/ledgers.
 *
 * One ledger per (account_holder, currency). beforeAll provisions a fresh
 * AccountHolder, whose synchronous onboard pipeline auto-materialises a USD
 * ledger. The CRUD tests operate on that auto-materialised row — POSTing a
 * second ledger on the same (AH, currency) hits the unique index → 422.
 * Update changes status (NOT currency, since the unique index on
 * (account_holder_id, currency) would conflict).
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest'

import { mintSecondaryTenant, type SecondaryTenant } from '@atomic-fi/sdk'

import { config } from '../src/env.ts'
import {
  apiKeyHeaders,
  bearerHeaders,
  createAccountHolder,
  postAdminSession,
  safeDelete,
  UUID_RE,
  warmupBlocklistCache,
  type AnyJson,
} from '../src/test-helpers.ts'

describe('ledgers — /api/ledgers', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let accountHolderId: string
  let ledgerId: string

  beforeAll(async () => {
    const session = await postAdminSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-ledgers',
    })

    await warmupBlocklistCache(bearer)
    const ah = await createAccountHolder(bearer, primaryTenantId)
    accountHolderId = ah.id
  })

  afterAll(async () => {
    if (ledgerId) await safeDelete(`/api/ledgers/${ledgerId}`, bearerHeaders(bearer))
    if (accountHolderId) await safeDelete(`/api/account-holders/${accountHolderId}`, bearerHeaders(bearer))
  })

  it('Onboarding auto-materialises a USD ledger; POST a duplicate → 422', async () => {
    // The AH was POSTed in beforeAll via createAccountHolder, which runs the
    // synchronous onboard pipeline. That pipeline materialises one ledger
    // per (account_holder, enabled_currency). Discover it via the index —
    // the GET /api/ledgers endpoint doesn't declare account_holder_id as a
    // query parameter today (OpenApiSpex would reject it), so scan the most
    // recent page client-side.
    const list = await fetch(
      `${config.baseUrl}/api/ledgers?page_size=100&order_by=inserted_at&order_directions=desc`,
      { headers: bearerHeaders(bearer) },
    )
    expect(list.status).toBe(200)
    const { data } = (await list.json()) as { data: AnyJson[] }
    const autoMat = data.find(
      (l) => l.currency === 'USD' && l.account_holder_id === accountHolderId,
    )
    expect(autoMat, 'onboarding should have created a USD ledger').toBeDefined()
    expect((autoMat as AnyJson).id as string).toMatch(UUID_RE)
    ledgerId = (autoMat as AnyJson).id as string

    // Attempting to create a second ledger on the same (AH, currency)
    // hits the unique index → 422 with "has already been taken".
    const dup = await fetch(`${config.baseUrl}/api/ledgers`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_holder_id: accountHolderId,
        currency: 'USD',
        status: 'active',
        tenant_id: primaryTenantId,
      }),
    })
    expect(dup.status).toBe(422)
  })

  it('GET /api/ledgers → 200 contains the auto-materialised ledger', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledgers?page_size=100&order_by=inserted_at&order_directions=desc`, { headers: bearerHeaders(bearer) })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[] }
    expect(body.data.some((l) => l.id === ledgerId)).toBe(true)
  })

  it('GET /api/ledgers/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledgers/${ledgerId}`, { headers: bearerHeaders(bearer) })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(ledgerId)
  })

  it('PUT /api/ledgers/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledgers/${ledgerId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_holder_id: accountHolderId,
        currency: 'USD',
        status: 'closed',
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.status).toBe('closed')
  })

  it('GET /api/ledgers?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledgers?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/ledgers → 422 on missing currency', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledgers`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({ account_holder_id: accountHolderId, tenant_id: primaryTenantId }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/ledgers/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledgers/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/ledgers → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledgers`, { headers: { accept: 'application/json' } })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary ledger → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledgers/${ledgerId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/ledgers/:id → 204 when no LA tree has been materialised yet', async () => {
    // An AH-only ledger (no Counterparty / PaymentAccount yet) has no
    // ledger_accounts referencing it, so the restrict-FK path doesn't fire
    // and DELETE succeeds. Once a CP or PA exists for this AH the auto-mat
    // pipeline writes LAs and this DELETE would 422 — see ledger_accounts
    // / payment_accounts test files for that branch.
    const del = await fetch(`${config.baseUrl}/api/ledgers/${ledgerId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status, await del.clone().text()).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/ledgers/${ledgerId}`, { headers: bearerHeaders(bearer) })
    expect(get.status).toBe(404)
    ledgerId = ''
  })
})
