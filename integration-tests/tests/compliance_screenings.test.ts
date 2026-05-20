/**
 * compliance_screenings — index + show + 3 stateful sync screen-by-id endpoints.
 *
 * The `/api/compliance-screenings/{account-holders|beneficial-owners|
 * counterparties}/:id/screen` endpoints invoke the full OnboardingContext
 * refresh pipeline (Watchman + RuleEngine + apply controls) and persist the
 * resulting screening row. We provision an AH (with nested LE), a BO, and a
 * CP in beforeAll, then exercise each by-id screen action.
 *
 * Watchman returns one of: pass | potential_match | blocked. We accept all
 * three so the spec stays green regardless of the custom screening list's
 * current contents.
 *
 * All seven screen endpoints (stateless preview + stateful sync) return the
 * project-standard `{data: [...], meta: {...}}` paginated envelope.
 */
import { beforeAll, describe, expect, it } from 'vitest'

import { mintSecondaryTenant, type SecondaryTenant } from '@atomic-fi/sdk'

import { config } from '../src/env.ts'
import {
  apiKeyHeaders,
  bearerHeaders,
  createAccountHolder,
  createBeneficialOwner,
  createCounterparty,
  postAdminSession,
  UUID_RE,
  type AnyJson,
} from '../src/test-helpers.ts'

// `screening_status` is the workflow state of the persisted row (pending
// until manual review). Watchman's match outcome lives in
// `sanctions_screening_status`. The by-id endpoints persist immediately so
// every fresh result sits at `pending`.
const VALID_STATUSES = ['pending', 'pass', 'potential_match', 'blocked']

describe('compliance_screenings — /api/compliance-screenings', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let accountHolderId: string
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

    // Initialize the per-tenant blocklist cache BEFORE any AH/CP/BO create.
    // AH/CP/BO POST runs OnboardingContext.onboard synchronously, which
    // requires the cache initialized (fail-closed by design).
    const refresh = await fetch(`${config.baseUrl}/api/tenants/refresh-blocklist-cache`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
    })
    if (!refresh.ok) {
      throw new Error(`refresh-blocklist-cache → ${refresh.status}: ${await refresh.text()}`)
    }

    const ah = await createAccountHolder(bearer, primaryTenantId)
    accountHolderId = ah.id

    const bo = await createBeneficialOwner(bearer, primaryTenantId, accountHolderId)
    beneficialOwnerId = bo.id

    const cp = await createCounterparty(bearer, primaryTenantId, accountHolderId)
    counterpartyId = cp.id
  })

  it('POST /api/compliance-screenings/account-holders/:id/screen → 200 (stateful, persists)', async () => {
    const res = await fetch(
      `${config.baseUrl}/api/compliance-screenings/account-holders/${accountHolderId}/screen`,
      { method: 'POST', headers: bearerHeaders(bearer) },
    )
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeGreaterThanOrEqual(1)
    const [first] = body.data
    expect(first.id).toMatch(UUID_RE)
    expect(first.scope).toBe('account_holder')
    expect(first.screening_type).toBe('sanctions')
    expect(VALID_STATUSES).toContain(first.screening_status as string)
    firstScreeningId = first.id as string
  })

  it('POST /api/compliance-screenings/beneficial-owners/:id/screen → 200', async () => {
    const res = await fetch(
      `${config.baseUrl}/api/compliance-screenings/beneficial-owners/${beneficialOwnerId}/screen`,
      { method: 'POST', headers: bearerHeaders(bearer) },
    )
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeGreaterThanOrEqual(1)
    expect(body.data[0].scope).toBe('beneficial_owner')
    expect(VALID_STATUSES).toContain(body.data[0].screening_status as string)
  })

  it('POST /api/compliance-screenings/counterparties/:id/screen → 200', async () => {
    const res = await fetch(
      `${config.baseUrl}/api/compliance-screenings/counterparties/${counterpartyId}/screen`,
      { method: 'POST', headers: bearerHeaders(bearer) },
    )
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeGreaterThanOrEqual(1)
    expect(body.data[0].scope).toBe('counterparty')
    expect(VALID_STATUSES).toContain(body.data[0].screening_status as string)
  })

  it('GET /api/compliance-screenings → 200 contains the prior screening', async (ctx) => {
    const res = await fetch(`${config.baseUrl}/api/compliance-screenings?page_size=100&order_by=inserted_at&order_directions=desc`, {
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
