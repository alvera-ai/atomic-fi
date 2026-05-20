/**
 * counterparties — full CRUD + RLS for /api/counterparties.
 *
 * Counterparty is created with a nested `legal_entity` object (cast_assoc).
 * The LE link is immutable post-create — PII replacement goes through
 * `PUT /api/counterparties/:id/legal-entity` (legal_entities.test.ts).
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest'

import { mintSecondaryTenant, type SecondaryTenant } from '@atomic-fi/sdk'

import { config } from '../src/env.ts'
import {
  apiKeyHeaders,
  bearerHeaders,
  createAccountHolder,
  defaultIndividualLegalEntity,
  postAdminSession,
  safeDelete,
  UUID_RE,
  warmupBlocklistCache,
  type AnyJson,
} from '../src/test-helpers.ts'

describe('counterparties — /api/counterparties', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let accountHolderId: string
  let counterpartyId: string

  beforeAll(async () => {
    const session = await postAdminSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-counterparties',
    })

    await warmupBlocklistCache(bearer)
    const ah = await createAccountHolder(bearer, primaryTenantId)
    accountHolderId = ah.id
  })

  afterAll(async () => {
    if (counterpartyId) await safeDelete(`/api/counterparties/${counterpartyId}`, bearerHeaders(bearer))
    if (accountHolderId) await safeDelete(`/api/account-holders/${accountHolderId}`, bearerHeaders(bearer))
  })

  it('POST /api/counterparties → 201', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        status: 'active',
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
        chain_screening: false,
        legal_entity: defaultIndividualLegalEntity(primaryTenantId, 'CP'),
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.status).toBe('active')
    counterpartyId = body.id as string
  })

  it('GET /api/counterparties → 200 contains created', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties?page_size=100&order_by=inserted_at&order_directions=desc`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[] }
    expect(body.data.some((c) => c.id === counterpartyId)).toBe(true)
  })

  it('GET /api/counterparties/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties/${counterpartyId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(counterpartyId)
  })

  it('PUT /api/counterparties/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties/${counterpartyId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        status: 'suspended',
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.status).toBe('suspended')
  })

  it('GET /api/counterparties?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/counterparties with nested legal_entity (cast_assoc) → 201', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        status: 'active',
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
        chain_screening: false,
        legal_entity: {
          legal_entity_type: 'individual',
          first_name: 'NestedCP',
          last_name: 'External',
          date_of_birth: '1985-03-15',
          citizenship_country: 'GB',
          politically_exposed_person: false,
          tenant_id: primaryTenantId,
        },
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect((body.legal_entity as AnyJson).first_name).toBe('NestedCP')
    expect((body.legal_entity as AnyJson).subject_type).toBe('counterparty')
    await safeDelete(`/api/counterparties/${body.id}`, bearerHeaders(bearer))
  })

  it('POST /api/counterparties is get-or-create on external_id → 201 returns same id', async () => {
    const number = `EXT-IDEMPOTENT-${Date.now()}`
    const post = (extra: Record<string, unknown>) =>
      fetch(`${config.baseUrl}/api/counterparties`, {
        method: 'POST',
        headers: bearerHeaders(bearer),
        body: JSON.stringify({
          status: 'active',
          account_holder_id: accountHolderId,
          tenant_id: primaryTenantId,
          external_id: number,
          chain_screening: false,
          legal_entity: defaultIndividualLegalEntity(primaryTenantId, 'GOC'),
          ...extra,
        }),
      })

    const res1 = await post({})
    expect(res1.status, await res1.clone().text()).toBe(201)
    const body1 = (await res1.json()) as AnyJson

    // Re-POST with same external_id but different status — returns
    // the original record unchanged (external SoE id wins; PUT for updates).
    const res2 = await post({ status: 'suspended', legal_entity: defaultIndividualLegalEntity(primaryTenantId, 'GOC2') })
    expect(res2.status).toBe(201)
    const body2 = (await res2.json()) as AnyJson

    expect(body2.id).toBe(body1.id)
    expect(body2.status).toBe('active')
    expect(body2.external_id).toBe(number)

    await safeDelete(`/api/counterparties/${body1.id as string}`, bearerHeaders(bearer))
  })

  it('POST /api/counterparties → 422 on missing status', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
        chain_screening: false,
        legal_entity: defaultIndividualLegalEntity(primaryTenantId, 'CPMissing'),
      }),
    })
    expect(res.status).toBe(422)
  })

  it('POST /api/counterparties → 422 when nested legal_entity is missing', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        status: 'active',
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
        chain_screening: false,
      }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/counterparties/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/counterparties → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties`, { headers: { accept: 'application/json' } })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary counterparty → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/counterparties/${counterpartyId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/counterparties/:id → 422 when ledger_accounts tree exists', async () => {
    // CP onboarding materialises ledger_accounts.counterparty_id when the
    // parent AH also has its tree materialised (it does — the AH was POSTed
    // through the controller in beforeAll). ON DELETE RESTRICT surfaces as
    // a changeset error → 422.
    const del = await fetch(`${config.baseUrl}/api/counterparties/${counterpartyId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status, await del.clone().text()).toBe(422)

    const body = (await del.json()) as { errors: { detail: string }[] }
    expect(body.errors.some((e) => e.detail.includes('exist for this counterparty'))).toBe(true)

    const get = await fetch(`${config.baseUrl}/api/counterparties/${counterpartyId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(get.status).toBe(200)
  })
})
