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
  createAccountHolder,
  postAdminSession,
  safeDelete,
  UUID_RE,
  warmupBlocklistCache,
  type AnyJson,
} from '../src/test-helpers.ts'

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

    await warmupBlocklistCache(bearer)
    const ah = await createAccountHolder(bearer, primaryTenantId)
    accountHolderId = ah.id

    // AH onboarding auto-materialises a USD ledger; discover it via the
    // index (account_holder_id isn't a declared query param on the GET).
    const list = await fetch(
      `${config.baseUrl}/api/ledgers?page_size=100&order_by=inserted_at&order_directions=desc`,
      { headers: bearerHeaders(bearer) },
    )
    if (!list.ok) throw new Error(`GET /api/ledgers → ${list.status}: ${await list.text()}`)
    const { data } = (await list.json()) as { data: AnyJson[] }
    const autoMat = data.find(
      (l) => l.currency === 'USD' && l.account_holder_id === accountHolderId,
    )
    if (!autoMat) throw new Error('expected onboarding to auto-materialise a USD ledger')
    ledgerId = autoMat.id as string
  })

  afterAll(async () => {
    if (accountId) await safeDelete(`/api/ledger-accounts/${accountId}`, bearerHeaders(bearer))
    if (ledgerId) await safeDelete(`/api/ledgers/${ledgerId}`, bearerHeaders(bearer))
    if (accountHolderId) await safeDelete(`/api/account-holders/${accountHolderId}`, bearerHeaders(bearer))
  })

  it('Onboarding auto-materialises root LAs; POST a duplicate → 422', async () => {
    // AH onboarding (via `ensure_linked_ledger_accounts`) materialises an
    // `account_holder_root` row per ledger plus one
    // `account_holder_regime_root` per enabled regime. The CRUD tests below
    // operate on that auto-mat tree — POSTing a row with the same
    // (ledger_id, regime, payment_account_id, counterparty_id) tuple hits
    // the partial unique index → 422 "has already been taken".
    const list = await fetch(
      `${config.baseUrl}/api/ledger-accounts?page_size=100&order_by=inserted_at&order_directions=desc`,
      { headers: bearerHeaders(bearer) },
    )
    expect(list.status).toBe(200)
    const { data } = (await list.json()) as { data: AnyJson[] }
    const autoMat = data.find(
      (la) => la.ledger_id === ledgerId && la.la_type === 'account_holder_root',
    )
    expect(autoMat, 'onboarding should materialise an account_holder_root LA').toBeDefined()
    accountId = (autoMat as AnyJson).id as string
    expect(accountId).toMatch(UUID_RE)

    // Duplicate POST on the same (ledger, regime, no-pa, no-cp) tuple → 422.
    const dup = await fetch(`${config.baseUrl}/api/ledger-accounts`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_holder_id: accountHolderId,
        ledger_id: ledgerId,
        currency: 'USD',
        regime: 'root',
        la_type: 'account_holder_root',
        status: 'active',
        tenant_id: primaryTenantId,
      }),
    })
    expect(dup.status).toBe(422)
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
        regime: 'root',
        la_type: 'account_holder_root',
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
        regime: 'ach',
        la_type: 'account_holder_regime_root',
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
