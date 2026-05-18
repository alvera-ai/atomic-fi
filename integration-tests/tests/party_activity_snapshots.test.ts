/**
 * party_activity_snapshots — full CRUD + RLS for /api/party-activity-snapshots.
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

const today = new Date().toISOString().slice(0, 10)
const monthAgo = new Date(Date.now() - 30 * 86_400_000).toISOString().slice(0, 10)

describe('party_activity_snapshots — /api/party-activity-snapshots', () => {
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
      prefix: 'rls-pas',
    })

    const le = await postJson('/api/legal-entities', bearerHeaders(bearer), {
      legal_entity_type: 'individual',
      first_name: 'PASParent',
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
    if (snapshotId) await safeDelete(`/api/party-activity-snapshots/${snapshotId}`, bearerHeaders(bearer))
  })

  it('POST /api/party-activity-snapshots → 201', async () => {
    const res = await fetch(`${config.baseUrl}/api/party-activity-snapshots`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_holder_id: accountHolderId,
        period_type: 'monthly',
        period_start: monthAgo,
        period_end: today,
        kyc_status_at_start: 'approved',
        kyc_status_at_end: 'approved',
        risk_level_at_start: 'low',
        risk_level_at_end: 'low',
        total_screenings: 4,
        screening_hits: 1,
        transaction_count: 20,
        total_debit_amount: 10000,
        total_credit_amount: 12000,
        high_risk_transaction_count: 2,
        sar_indicator: false,
        notes: 'monthly review',
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.period_type).toBe('monthly')
    expect(body.screening_hits).toBe(1)
    snapshotId = body.id as string
  })

  it('GET /api/party-activity-snapshots → 200 contains created', async () => {
    const res = await fetch(
      `${config.baseUrl}/api/party-activity-snapshots?page_size=100&order_by=inserted_at&order_directions=desc`,
      { headers: bearerHeaders(bearer) },
    )
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[] }
    expect(body.data.some((s) => s.id === snapshotId)).toBe(true)
  })

  it('GET /api/party-activity-snapshots/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/party-activity-snapshots/${snapshotId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(snapshotId)
  })

  it('PUT /api/party-activity-snapshots/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/party-activity-snapshots/${snapshotId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_holder_id: accountHolderId,
        period_type: 'monthly',
        period_start: monthAgo,
        period_end: today,
        kyc_status_at_start: 'approved',
        kyc_status_at_end: 'approved',
        risk_level_at_start: 'low',
        risk_level_at_end: 'medium',
        total_screenings: 5,
        screening_hits: 2,
        transaction_count: 25,
        total_debit_amount: 15000,
        total_credit_amount: 17000,
        high_risk_transaction_count: 3,
        sar_indicator: true,
        notes: 'updated review',
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.sar_indicator).toBe(true)
    expect(body.risk_level_at_end).toBe('medium')
  })

  it('GET /api/party-activity-snapshots?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/party-activity-snapshots?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/party-activity-snapshots → 422 on missing required', async () => {
    const res = await fetch(`${config.baseUrl}/api/party-activity-snapshots`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({ tenant_id: primaryTenantId }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/party-activity-snapshots/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/party-activity-snapshots/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/party-activity-snapshots → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/party-activity-snapshots`, {
      headers: { accept: 'application/json' },
    })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary snapshot → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/party-activity-snapshots/${snapshotId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/party-activity-snapshots/:id → 204 + GET 404', async () => {
    const del = await fetch(`${config.baseUrl}/api/party-activity-snapshots/${snapshotId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/party-activity-snapshots/${snapshotId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(get.status).toBe(404)
    snapshotId = ''
  })
})
