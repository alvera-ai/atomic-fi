/**
 * ledger_account_balances — READ-ONLY for /api/ledger-account-balances.
 *
 * Index + show are the only actions; balance rows are trigger-maintained on
 * ledger_entry insert/update. We provision a fresh entry in beforeAll to
 * guarantee at least one balance row exists for our tenant.
 */
import { beforeAll, describe, expect, it } from 'vitest'

import { mintSecondaryTenant, type SecondaryTenant } from '@atomic-fi/sdk'

import { config } from '../src/env.ts'
import {
  apiKeyHeaders,
  bearerHeaders,
  createAccountHolder,
  postAdminSession,
  warmupBlocklistCache,
  type AnyJson,
} from '../src/test-helpers.ts'

async function postJson(path: string, headers: Record<string, string>, body: unknown): Promise<AnyJson> {
  const res = await fetch(`${config.baseUrl}${path}`, { method: 'POST', headers, body: JSON.stringify(body) })
  if (!res.ok) throw new Error(`${path} → ${res.status}: ${await res.text()}`)
  return (await res.json()) as AnyJson
}

describe('ledger_account_balances — /api/ledger-account-balances', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let ledgerAccountId: string
  let firstBalanceId: string | undefined

  beforeAll(async () => {
    const session = await postAdminSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-balances',
    })

    await warmupBlocklistCache(bearer)
    const ah = await createAccountHolder(bearer, primaryTenantId)

    // AH onboarding auto-materialises an `account_holder_root` ledger_account.
    // Discover it via the index — neither /api/ledgers nor /api/ledger-accounts
    // declare account_holder_id as a query param, so scan recent rows.
    const list = await fetch(
      `${config.baseUrl}/api/ledger-accounts?page_size=100&order_by=inserted_at&order_directions=desc`,
      { headers: bearerHeaders(bearer) },
    )
    if (!list.ok) throw new Error(`GET /api/ledger-accounts → ${list.status}: ${await list.text()}`)
    const { data } = (await list.json()) as { data: AnyJson[] }
    const autoMat = data.find(
      (la) => la.account_holder_id === ah.id && la.la_type === 'account_holder_root',
    )
    if (!autoMat) throw new Error('expected onboarding to materialise an account_holder_root LA')
    ledgerAccountId = autoMat.id as string

    // Trigger a balance row by writing a ledger_entry against the auto-mat LA.
    await postJson('/api/ledger-entries', bearerHeaders(bearer), {
      account_holder_id: ah.id,
      ledger_account_id: ledgerAccountId,
      currency: 'USD',
      amount: 1000,
      entry_type: 'credit',
      status: 'posted',
      entry_date: '2026-05-01',
      tenant_id: primaryTenantId,
    })
  })

  it('GET /api/ledger-account-balances → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-account-balances?page_size=100&order_by=inserted_at&order_directions=desc`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(Array.isArray(body.data)).toBe(true)
    const ours = body.data.find((b) => b.ledger_account_id === ledgerAccountId)
    expect(ours).toBeDefined()
    firstBalanceId = ours?.id as string
  })

  it('GET /api/ledger-account-balances/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-account-balances/${firstBalanceId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(firstBalanceId)
    expect(body.ledger_account_id).toBe(ledgerAccountId)
  })

  it('GET /api/ledger-account-balances?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-account-balances?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('GET /api/ledger-account-balances/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-account-balances/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/ledger-account-balances → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-account-balances`, {
      headers: { accept: 'application/json' },
    })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary balance → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/ledger-account-balances/${firstBalanceId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })
})
