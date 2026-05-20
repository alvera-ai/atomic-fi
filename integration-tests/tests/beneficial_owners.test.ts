/**
 * beneficial_owners — full CRUD + RLS for /api/beneficial-owners.
 *
 * BO is created with a nested `legal_entity` object (cast_assoc). The LE
 * link is immutable post-create — PII replacement goes through
 * `PUT /api/beneficial-owners/:id/legal-entity`.
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
  type AnyJson,
} from '../src/test-helpers.ts'

describe('beneficial_owners — /api/beneficial-owners', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let accountHolderId: string
  let ownerId: string

  beforeAll(async () => {
    const session = await postAdminSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-beneficial-owners',
    })

    const ah = await createAccountHolder(bearer, primaryTenantId)
    accountHolderId = ah.id
  })

  afterAll(async () => {
    if (ownerId) await safeDelete(`/api/beneficial-owners/${ownerId}`, bearerHeaders(bearer))
    if (accountHolderId) await safeDelete(`/api/account-holders/${accountHolderId}`, bearerHeaders(bearer))
  })

  it('POST /api/beneficial-owners → 201', async () => {
    const res = await fetch(`${config.baseUrl}/api/beneficial-owners`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        control_type: 'shareholder',
        ownership_pct: 25.0,
        verification_status: 'pending',
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
        legal_entity: defaultIndividualLegalEntity(primaryTenantId, 'BO'),
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.control_type).toBe('shareholder')
    expect(body.ownership_pct).toBe(25.0)
    ownerId = body.id as string
  })

  it('GET /api/beneficial-owners → 200 contains created', async () => {
    const res = await fetch(`${config.baseUrl}/api/beneficial-owners?page_size=100&order_by=inserted_at&order_directions=desc`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[] }
    expect(body.data.some((o) => o.id === ownerId)).toBe(true)
  })

  it('GET /api/beneficial-owners/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/beneficial-owners/${ownerId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(ownerId)
  })

  it('PUT /api/beneficial-owners/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/beneficial-owners/${ownerId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        control_type: 'director',
        ownership_pct: 51.0,
        verification_status: 'verified',
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.control_type).toBe('director')
    expect(body.verification_status).toBe('verified')
  })

  it('GET /api/beneficial-owners?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/beneficial-owners?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/beneficial-owners → 422 on missing control_type', async () => {
    const res = await fetch(`${config.baseUrl}/api/beneficial-owners`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        ownership_pct: 10,
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
        legal_entity: defaultIndividualLegalEntity(primaryTenantId, 'BOMissing'),
      }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/beneficial-owners/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/beneficial-owners/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/beneficial-owners → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/beneficial-owners`, { headers: { accept: 'application/json' } })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary owner → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/beneficial-owners/${ownerId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/beneficial-owners/:id → 204 + GET 404', async () => {
    const del = await fetch(`${config.baseUrl}/api/beneficial-owners/${ownerId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/beneficial-owners/${ownerId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(get.status).toBe(404)
    ownerId = ''
  })
})
