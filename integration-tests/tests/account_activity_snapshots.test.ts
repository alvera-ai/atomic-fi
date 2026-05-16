/**
 * account_activity_snapshots — full CRUD + RLS for /api/account-activity-snapshots.
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

const periodEnd = new Date().toISOString()
const periodStart = new Date(Date.now() - 86_400_000).toISOString()

describe('account_activity_snapshots — /api/account-activity-snapshots', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let accountHolderId: string
  let snapshotId: string

  beforeAll(async () => {
    const session = await postAdminSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-aas',
    })

    const le = await postJson('/api/legal-entities', bearerHeaders(bearer), {
      legal_entity_type: 'individual',
      first_name: 'AASParent',
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
  })

  afterAll(async () => {
    if (snapshotId) await safeDelete(`/api/account-activity-snapshots/${snapshotId}`, bearerHeaders(bearer))
  })

  it('POST /api/account-activity-snapshots → 201', async () => {
    const res = await fetch(`${config.baseUrl}/api/account-activity-snapshots`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        snapshot_type: 'daily',
        period_start: periodStart,
        period_end: periodEnd,
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.snapshot_type).toBe('daily')
    snapshotId = body.id as string
  })

  it('GET /api/account-activity-snapshots → 200 contains created', async () => {
    const res = await fetch(
      `${config.baseUrl}/api/account-activity-snapshots?page_size=100&order_by=inserted_at&order_directions=desc`,
      { headers: bearerHeaders(bearer) },
    )
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[] }
    expect(body.data.some((s) => s.id === snapshotId)).toBe(true)
  })

  it('GET /api/account-activity-snapshots/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/account-activity-snapshots/${snapshotId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(snapshotId)
  })

  it('PUT /api/account-activity-snapshots/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/account-activity-snapshots/${snapshotId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        snapshot_type: 'daily',
        status: 'computed',
        period_start: periodStart,
        period_end: periodEnd,
        total_debit_count: 5,
        total_credit_count: 3,
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.status).toBe('computed')
    expect(body.total_debit_count).toBe(5)
  })

  it('GET /api/account-activity-snapshots?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/account-activity-snapshots?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/account-activity-snapshots → 422 on missing snapshot_type', async () => {
    const res = await fetch(`${config.baseUrl}/api/account-activity-snapshots`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        period_start: periodStart,
        period_end: periodEnd,
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/account-activity-snapshots/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/account-activity-snapshots/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/account-activity-snapshots → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/account-activity-snapshots`, {
      headers: { accept: 'application/json' },
    })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary snapshot → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/account-activity-snapshots/${snapshotId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/account-activity-snapshots/:id → 204 + GET 404', async () => {
    const del = await fetch(`${config.baseUrl}/api/account-activity-snapshots/${snapshotId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/account-activity-snapshots/${snapshotId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(get.status).toBe(404)
    snapshotId = ''
  })
})
